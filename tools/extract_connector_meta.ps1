param(
  [string]$Endpoint = "http://127.0.0.1:8000/api/chat",
  [string[]]$Providers = @("claude","gemini"),
  [string]$Prompt = "connector meta probe: pong",
  [int]$TimeoutSec = 35,
  [int]$MaxNodes = 12000,
  [int]$MaxHitsPerProvider = 12
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-ChatOnce {
  param([string]$ProviderLocal)

  $body = @{
    provider = $ProviderLocal
    model    = ""
    messages = @(@{ role="user"; content=$Prompt })
  }

  $json = $body | ConvertTo-Json -Depth 40 -Compress
  return (Invoke-RestMethod -Method Post -Uri $Endpoint -ContentType "application/json" -Body $json -TimeoutSec $TimeoutSec)
}

function Get-Props {
  param($Obj)
  try { return $Obj.PSObject.Properties.Name } catch { return @() }
}

function Is-Iterable {
  param($Obj)
  if ($null -eq $Obj) { return $false }
  if ($Obj -is [string]) { return $false }
  return ($Obj -is [System.Collections.IEnumerable])
}

function Walk-Json {
  param(
    [Parameter(Mandatory=$true)]$Root,
    [int]$Max = 12000
  )

  $q = New-Object System.Collections.Generic.Queue[object]
  $q.Enqueue(@{ path="$"; node=$Root }) | Out-Null

  $seen = 0
  $hits = New-Object System.Collections.Generic.List[object]

  while ($q.Count -gt 0) {
    $cur  = $q.Dequeue()
    $path = $cur.path
    $node = $cur.node

    $seen++
    if ($seen -gt $Max) { break }
    if ($null -eq $node) { continue }

    if ($node -is [psobject]) {
      $props = Get-Props $node
      foreach ($k in $props) {
        $val = $null
        try { $val = $node.$k } catch { continue }

        $p2 = $path + "." + $k

        if ($k -in @("connectorMeta","connector_meta","scorecard","router","schema_version","schemaVersion")) {
          $hits.Add([pscustomobject]@{ path=$p2; key=$k; kind=($val.GetType().Name) }) | Out-Null
        }

        if ($val -is [psobject]) {
          $q.Enqueue(@{ path=$p2; node=$val }) | Out-Null
          continue
        }

        if (Is-Iterable $val) {
          $idx = 0
          foreach ($it in $val) {
            if ($idx -ge 200) { break }
            $q.Enqueue(@{ path=("$p2" + "[" + $idx + "]"); node=$it }) | Out-Null
            $idx++
          }
        }
      }
      continue
    }

    if (Is-Iterable $node) {
      $idx = 0
      foreach ($it in $node) {
        if ($idx -ge 200) { break }
        $q.Enqueue(@{ path=("$path" + "[" + $idx + "]"); node=$it }) | Out-Null
        $idx++
      }
      continue
    }
  }

  return [pscustomobject]@{ seen=$seen; hits=$hits }
}

function Try-Get {
  param($Obj, [string]$Key)
  try {
    $props = Get-Props $Obj
    if ($props -contains $Key) { return $Obj.$Key }
  } catch {}
  return $null
}

function Summarize-ConnectorMeta {
  param([string]$Provider, [string]$Path, $Meta)

  $ok = Try-Get $Meta "ok"
  if ($null -eq $ok) { $ok = Try-Get $Meta "success" }

  $used_stub = Try-Get $Meta "used_stub"
  if ($null -eq $used_stub) { $used_stub = Try-Get $Meta "stub" }

  $http_status = Try-Get $Meta "http_status"
  if ($null -eq $http_status) { $http_status = Try-Get $Meta "status" }

  $http_body = Try-Get $Meta "http_body_snippet"
  if ($null -eq $http_body) { $http_body = Try-Get $Meta "body_snippet" }

  $model = Try-Get $Meta "model"

  [pscustomobject]@{
    provider = $Provider
    connectorMetaPath = $Path
    ok = $ok
    used_stub = $used_stub
    http_status = $http_status
    http_body_snippet = if ($null -eq $http_body) { $null } else {
      $s = $http_body.ToString()
      $s.Substring(0, [Math]::Min(160, $s.Length))
    }
    model = $model
  }
}

$rows = New-Object System.Collections.Generic.List[object]

foreach ($p in $Providers) {
  Write-Host ""
  Write-Host ("=== CALL: {0} ===" -f $p)

  $resp = $null
  try { $resp = Invoke-ChatOnce -ProviderLocal $p } catch {
    $rows.Add([pscustomobject]@{ provider=$p; connectorMetaPath=$null; ok=$false; used_stub=$null; http_status=$null; http_body_snippet=$null; model=$null }) | Out-Null
    Write-Host ("call failed: {0}" -f $_.Exception.Message)
    continue
  }

  $walk = Walk-Json -Root $resp -Max $MaxNodes
  Write-Host ("nodes_seen: {0}" -f $walk.seen)

  $hits = $walk.hits | Where-Object { $_.key -in @("connectorMeta","connector_meta") } | Select-Object -First $MaxHitsPerProvider
  if ($null -eq $hits -or $hits.Count -eq 0) {
    Write-Host "connectorMeta hits: 0"
    $rows.Add([pscustomobject]@{ provider=$p; connectorMetaPath=$null; ok=$null; used_stub=$null; http_status=$null; http_body_snippet=$null; model=$null }) | Out-Null
    continue
  }

  Write-Host ("connectorMeta hits: {0}" -f $hits.Count)

  foreach ($h in $hits) {
    $path = $h.path
    $cur = $resp
    $okPath = $true

    $tok = $path -replace '^\$\.', ''
    $parts = $tok -split '\.'

    foreach ($part in $parts) {
      if ($part -match '(.+)\[(\d+)\]$') {
        $name = $Matches[1]
        $idx  = [int]$Matches[2]
        try { $cur = $cur.$name } catch { $okPath = $false; break }
        try { $cur = $cur[$idx] } catch { $okPath = $false; break }
      } else {
        try { $cur = $cur.$part } catch { $okPath = $false; break }
      }
    }

    if (-not $okPath -or $null -eq $cur) { continue }

    $rows.Add((Summarize-ConnectorMeta -Provider $p -Path $path -Meta $cur)) | Out-Null
    break
  }
}

Write-Host ""
Write-Host "=== connectorMeta quick extract (1 row per provider) ==="
$rows | Format-Table -AutoSize