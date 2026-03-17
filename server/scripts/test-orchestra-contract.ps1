param(
  [string]$Uri = "http://localhost:8000/api/chat"
)

function Get-DerivedMap {
  param([object]$Response)

  $map = @{}
  foreach ($d in @($Response.derived)) {
    if ($null -ne $d -and $null -ne $d.key) {
      $map[[string]$d.key] = $d.value
    }
  }
  return $map
}

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

function Invoke-OrchestraCase {
  param(
    [string]$CaseName,
    [hashtable]$BodyObject
  )

  $body = $BodyObject | ConvertTo-Json -Depth 100

  $httpResponse = Invoke-WebRequest `
    -Method Post `
    -Uri $Uri `
    -ContentType "application/json; charset=utf-8" `
    -Body $body `
    -SkipHttpErrorCheck

  $statusCode = [int]$httpResponse.StatusCode
  $contentText = [string]$httpResponse.Content

  if ($statusCode -lt 200 -or $statusCode -ge 300) {
    throw "HTTP 호출 실패: $Uri :: status=$statusCode`n----- server error body -----`n$contentText"
  }

  if ([string]::IsNullOrWhiteSpace($contentText)) {
    throw "HTTP 호출 실패: $Uri :: 빈 응답 본문"
  }

  try {
    $response = $contentText | ConvertFrom-Json -Depth 100
  }
  catch {
    throw "JSON 파싱 실패: $Uri`n----- raw response body -----`n$contentText"
  }

  $derivedMap = Get-DerivedMap -Response $response

  [pscustomobject]@{
    caseName   = $CaseName
    response   = $response
    derivedMap = $derivedMap
  }
}

function Get-ProviderModelKey {
  param([object]$Item)

  if ($null -eq $Item) {
    return ""
  }

  return ([string]$Item.provider + "|" + [string]$Item.model)
}

function Test-RunnerUpExistsInScored {
  param(
    [object]$RunnerUp,
    [object[]]$Scored
  )

  if ($null -eq $RunnerUp) {
    return $false
  }

  $runnerKey = Get-ProviderModelKey -Item $RunnerUp

  foreach ($item in @($Scored)) {
    $itemKey = Get-ProviderModelKey -Item $item
    if ($itemKey -eq $runnerKey) {
      return $true
    }
  }

  return $false
}

function Get-HasAlternativeCandidate {
  param([object[]]$Scored)

  if ($null -eq $Scored -or $Scored.Count -lt 2) {
    return $false
  }

  $winnerKey = Get-ProviderModelKey -Item $Scored[0]

  for ($i = 1; $i -lt $Scored.Count; $i++) {
    $candidateKey = Get-ProviderModelKey -Item $Scored[$i]
    if ($candidateKey -ne $winnerKey) {
      return $true
    }
  }

  return $false
}

function Assert-CommonContract {
  param(
    [string]$CaseName,
    [object]$CaseObject
  )

  $map = $CaseObject.derivedMap
  $response = $CaseObject.response

  Assert-True ($null -ne $map["decision_log"]) "${CaseName}: decision_log 누락"
  Assert-True ($null -ne $map["final_answer_strategy_result"]) "${CaseName}: final_answer_strategy_result 누락"
  Assert-True ($null -ne $map["judge_winner_snapshot"]) "${CaseName}: judge_winner_snapshot 누락"
  Assert-True ($null -ne $map["final_answer_input_summary"]) "${CaseName}: final_answer_input_summary 누락"
  Assert-True ($null -ne $map["synthesis_trace"]) "${CaseName}: synthesis_trace 누락"
  Assert-True ($null -ne $map["conflict_summary"]) "${CaseName}: conflict_summary 누락"
  Assert-True ($null -ne $map["judge_trace"]) "${CaseName}: judge_trace 누락"

  $answerText = [string]$response.answer

  Assert-True (-not ($answerText -match "\[AI ORCHESTRA synthesis\]")) "${CaseName}: synthesis 블록 오염"
  Assert-True (-not ($answerText -match "winner=")) "${CaseName}: winner 메타 오염"
  Assert-True (-not ($answerText -match "runner_up=")) "${CaseName}: runner_up 메타 오염"
  Assert-True (-not ($answerText -match "judge_rationale=")) "${CaseName}: judge_rationale 메타 오염"
  Assert-True (-not ($answerText -match "judge_top_scores=")) "${CaseName}: judge_top_scores 메타 오염"
  Assert-True (-not ($answerText -match "judge_conflicts=")) "${CaseName}: judge_conflicts 메타 오염"

  $judgeTrace = $map["judge_trace"]
  $judgeCompleted = @($judgeTrace.events | Where-Object { $_.event_type -eq "judge_completed" } | Select-Object -First 1)[0]
  $winnerSnapshot = $map["judge_winner_snapshot"]
  $runnerUpSnapshot = $map["judge_runner_up_snapshot"]

  if ($null -ne $judgeCompleted) {
    $scored = @($judgeCompleted.details.scored)
    Assert-True ($scored.Count -ge 1) "${CaseName}: judge scored 후보 없음"

    Assert-True ([string]$winnerSnapshot.provider -eq [string]$scored[0].provider) "${CaseName}: winner provider 불일치"
    Assert-True ([string]$winnerSnapshot.model -eq [string]$scored[0].model) "${CaseName}: winner model 불일치"

    $winnerKey = Get-ProviderModelKey -Item $winnerSnapshot
    $hasAlternativeCandidate = Get-HasAlternativeCandidate -Scored $scored

    if (-not $hasAlternativeCandidate) {
      Assert-True ($null -eq $runnerUpSnapshot) "${CaseName}: 대체 후보가 없으므로 runner_up_snapshot 는 null 이어야 함"
    }
    else {
      Assert-True ($null -ne $runnerUpSnapshot) "${CaseName}: runner_up_snapshot 누락"
      Assert-True (
        (Get-ProviderModelKey -Item $runnerUpSnapshot) -ne $winnerKey
      ) "${CaseName}: winner 와 runner_up provider/model 중복"
      Assert-True (
        (Test-RunnerUpExistsInScored -RunnerUp $runnerUpSnapshot -Scored $scored)
      ) "${CaseName}: runner_up_snapshot 이 scored 목록에 없음"
    }
  }

  return $true
}

function Assert-NaturalCase {
  param(
    [string]$CaseName,
    [object]$CaseObject
  )

  $map = $CaseObject.derivedMap
  $response = $CaseObject.response

  $strategy = [string]$map["final_answer_strategy_result"].strategy
  $unresolved = [int]$map["conflict_summary"].unresolved_conflicts_count
  $hasReviewNote = ([string]$response.answer -match "\[검토 메모\]")
  $conflictDecisionCount = @($response.decisions | Where-Object { $_.entity -eq "final_answer_conflict_policy" }).Count

  Assert-True (
    ($strategy -eq "winner_pass_through") -or
    ($strategy -eq "conflict_aware_synthesis")
  ) "${CaseName}: strategy 값이 허용 범위 밖"

  if ($unresolved -eq 0) {
    Assert-True ($strategy -eq "winner_pass_through") "${CaseName}: unresolved=0 인데 strategy가 winner_pass_through가 아님"
    Assert-True (-not $hasReviewNote) "${CaseName}: unresolved=0 인데 검토 메모가 붙음"
    Assert-True ($conflictDecisionCount -eq 0) "${CaseName}: unresolved=0 인데 final_answer_conflict_policy가 있음"
  }
  else {
    Assert-True ($strategy -eq "conflict_aware_synthesis") "${CaseName}: unresolved>0 인데 strategy가 conflict_aware_synthesis가 아님"
    Assert-True ($hasReviewNote) "${CaseName}: unresolved>0 인데 검토 메모 누락"
    Assert-True ($conflictDecisionCount -ge 1) "${CaseName}: unresolved>0 인데 final_answer_conflict_policy 누락"
  }

  return $true
}

function Assert-ForcedConflictCase {
  param(
    [string]$CaseName,
    [object]$CaseObject
  )

  $map = $CaseObject.derivedMap
  $response = $CaseObject.response

  $unresolved = [int]$map["conflict_summary"].unresolved_conflicts_count
  $strategy = [string]$map["final_answer_strategy_result"].strategy
  $hasReviewNote = ([string]$response.answer -match "\[검토 메모\]")
  $conflictDecisionCount = @($response.decisions | Where-Object { $_.entity -eq "final_answer_conflict_policy" }).Count

  Assert-True ($unresolved -gt 0) "${CaseName}: forced conflict가 반영되지 않았습니다."
  Assert-True ($strategy -eq "conflict_aware_synthesis") "${CaseName}: strategy 불일치"
  Assert-True ($hasReviewNote) "${CaseName}: 검토 메모 누락"
  Assert-True ($conflictDecisionCount -ge 1) "${CaseName}: final_answer_conflict_policy 누락"

  return $true
}

$commonProviders = @("openai","perplexity","claude","gemini")

$naturalPrompt = @"
최신 벤치마크 수치나 구체적 점수는 단정하지 말고,
AI 오케스트레이션에서 OpenAI, Claude, Gemini, Perplexity의 역할을
reasoning 관점에서 어떻게 분담하는 것이 적합한지 원칙 중심으로 비교 평가해줘.
출력은 정성 비교와 역할 추천 중심으로 작성해줘.
"@

$forcedConflictPrompt = @"
세 모델이 서로 다른 수치나 비교 결론을 내리기 쉬운 주제로
2026년 AI 모델들의 reasoning 성능을 비교하고
가장 적합한 조합을 평가해줘.
수치와 벤치마크를 포함해.
"@

$localNatural = Invoke-OrchestraCase -CaseName "local_natural_case" -BodyObject @{
  mode = "orchestra_debug"
  providers = $commonProviders
  messages = @(
    @{
      role = "user"
      content = $naturalPrompt
    }
  )
}

$localConflict = Invoke-OrchestraCase -CaseName "local_conflict_aware_synthesis" -BodyObject @{
  mode = "orchestra_debug"
  force_conflict_for_test = $true
  providers = $commonProviders
  messages = @(
    @{
      role = "user"
      content = $forcedConflictPrompt
    }
  )
}

$runtimeNatural = Invoke-OrchestraCase -CaseName "runtime_natural_case" -BodyObject @{
  mode = "chat"
  task = "reasoning"
  providers = $commonProviders
  messages = @(
    @{
      role = "user"
      content = $naturalPrompt
    }
  )
}

$runtimeConflict = Invoke-OrchestraCase -CaseName "runtime_conflict_aware_synthesis" -BodyObject @{
  mode = "chat"
  task = "reasoning"
  force_conflict_for_test = $true
  providers = $commonProviders
  messages = @(
    @{
      role = "user"
      content = $forcedConflictPrompt
    }
  )
}

Assert-CommonContract -CaseName "local_natural_case" -CaseObject $localNatural | Out-Null
Assert-CommonContract -CaseName "local_conflict_aware_synthesis" -CaseObject $localConflict | Out-Null
Assert-CommonContract -CaseName "runtime_natural_case" -CaseObject $runtimeNatural | Out-Null
Assert-CommonContract -CaseName "runtime_conflict_aware_synthesis" -CaseObject $runtimeConflict | Out-Null

Assert-NaturalCase -CaseName "local_natural_case" -CaseObject $localNatural | Out-Null
Assert-ForcedConflictCase -CaseName "local_conflict_aware_synthesis" -CaseObject $localConflict | Out-Null
Assert-NaturalCase -CaseName "runtime_natural_case" -CaseObject $runtimeNatural | Out-Null
Assert-ForcedConflictCase -CaseName "runtime_conflict_aware_synthesis" -CaseObject $runtimeConflict | Out-Null

$result = [pscustomobject]@{
  ok = $true
  uri = $Uri
  local_natural_case = [pscustomobject]@{
    strategy = $localNatural.derivedMap["final_answer_strategy_result"].strategy
    unresolved_conflicts_count = $localNatural.derivedMap["conflict_summary"].unresolved_conflicts_count
    has_conflict_policy_decision = (@($localNatural.response.decisions | Where-Object { $_.entity -eq "final_answer_conflict_policy" }).Count -ge 1)
    answer_length = ([string]$localNatural.response.answer).Length
  }
  local_conflict_case = [pscustomobject]@{
    strategy = $localConflict.derivedMap["final_answer_strategy_result"].strategy
    unresolved_conflicts_count = $localConflict.derivedMap["conflict_summary"].unresolved_conflicts_count
    has_conflict_policy_decision = (@($localConflict.response.decisions | Where-Object { $_.entity -eq "final_answer_conflict_policy" }).Count -ge 1)
    answer_length = ([string]$localConflict.response.answer).Length
  }
  runtime_natural_case = [pscustomobject]@{
    strategy = $runtimeNatural.derivedMap["final_answer_strategy_result"].strategy
    unresolved_conflicts_count = $runtimeNatural.derivedMap["conflict_summary"].unresolved_conflicts_count
    has_conflict_policy_decision = (@($runtimeNatural.response.decisions | Where-Object { $_.entity -eq "final_answer_conflict_policy" }).Count -ge 1)
    answer_length = ([string]$runtimeNatural.response.answer).Length
  }
  runtime_conflict_case = [pscustomobject]@{
    strategy = $runtimeConflict.derivedMap["final_answer_strategy_result"].strategy
    unresolved_conflicts_count = $runtimeConflict.derivedMap["conflict_summary"].unresolved_conflicts_count
    has_conflict_policy_decision = (@($runtimeConflict.response.decisions | Where-Object { $_.entity -eq "final_answer_conflict_policy" }).Count -ge 1)
    answer_length = ([string]$runtimeConflict.response.answer).Length
  }
  judge_snapshot = [pscustomobject]@{
    local_winner_provider = $localNatural.derivedMap["judge_winner_snapshot"].provider
    local_winner_model = $localNatural.derivedMap["judge_winner_snapshot"].model
    local_runner_up_provider = if ($null -ne $localNatural.derivedMap["judge_runner_up_snapshot"]) { $localNatural.derivedMap["judge_runner_up_snapshot"].provider } else { $null }
    local_runner_up_model = if ($null -ne $localNatural.derivedMap["judge_runner_up_snapshot"]) { $localNatural.derivedMap["judge_runner_up_snapshot"].model } else { $null }
    runtime_winner_provider = $runtimeNatural.derivedMap["judge_winner_snapshot"].provider
    runtime_winner_model = $runtimeNatural.derivedMap["judge_winner_snapshot"].model
    runtime_runner_up_provider = if ($null -ne $runtimeNatural.derivedMap["judge_runner_up_snapshot"]) { $runtimeNatural.derivedMap["judge_runner_up_snapshot"].provider } else { $null }
    runtime_runner_up_model = if ($null -ne $runtimeNatural.derivedMap["judge_runner_up_snapshot"]) { $runtimeNatural.derivedMap["judge_runner_up_snapshot"].model } else { $null }
  }
}

$result | ConvertTo-Json -Depth 100
