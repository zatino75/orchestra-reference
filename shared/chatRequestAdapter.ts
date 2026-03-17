/**
 * 서버(/api/chat)에서 요청 바디를 "표준 형태"로 통일하기 위한 어댑터.
 *
 * 목표:
 * - 클라이언트가 보내는 chat_request@1.0 지원
 * - 기존 레거시 {message, input_assets}도 지원
 * - 어떤 형태로 와도 서버 로직은 아래 표준만 보면 되게 만들기
 *
 * 표준: AdaptedChatRequest
 */

export type InputAssetPayload = {
  asset_id: string;
  asset_type: string; // "table" | "document" | "research" | "schema" | "code" | "plan" (클라 기준)
  title: string;
  description: string;
  created_at: string;
  created_turn_id: string;
  payload: any;
  tags: string[];
  reusable: boolean;
};

export type AdaptedChatRequest = {
  schema_version: "chat_request@1.0" | "legacy@0";
  message: string;
  input_assets: string[];
  input_asset_payloads: InputAssetPayload[];
  // 서버가 필요하면 컨텍스트도 여기에 붙일 수 있음
  context: Record<string, any>;
};

/**
 * raw body(any)를 표준 요청으로 변환
 */
export function adaptChatRequest(raw: any): AdaptedChatRequest {
  const message =
    pickString(raw?.message) ??
    pickString(raw?.text) ??
    pickString(raw?.prompt) ??
    pickString(raw?.query) ??
    "";

  const input_assets = uniqStrings(
    asStringArray(raw?.input_assets) ??
      asStringArray(raw?.inputAssets) ??
      asStringArray(raw?.assets) ??
      []
  );

  const input_asset_payloads = asAssetPayloadArray(raw?.input_asset_payloads ?? raw?.inputAssetPayloads ?? []);

  const context: Record<string, any> = isPlainObject(raw?.context) ? raw.context : {};
  // 프로젝트 컨텍스트가 있을 수도 있음(기존 코드 호환)
  if (isPlainObject(raw?.project_context)) context.project_context = raw.project_context;
  if (isPlainObject(raw?.projectContext)) context.project_context = raw.projectContext;

  const schema_version =
    raw?.schema_version === "chat_request@1.0" ? ("chat_request@1.0" as const) : ("legacy@0" as const);

  return {
    schema_version,
    message,
    input_assets,
    input_asset_payloads,
    context,
  };
}

/**
 * input_asset_payloads를 LLM 프롬프트에 안전하게 직렬화(서버에서 사용)
 * - "이 자산 기반으로 다시 작업" 흐름을 만들 때 핵심.
 * - 너무 길어지지 않게 기본 제한 포함.
 */
export function renderInputAssetsForPrompt(args: {
  input_asset_payloads: InputAssetPayload[];
  max_chars_total?: number;
  max_rows_per_table?: number;
}): string {
  const max_chars_total = clampInt(args.max_chars_total ?? 12000, 2000, 50000);
  const max_rows_per_table = clampInt(args.max_rows_per_table ?? 50, 5, 500);

  const parts: string[] = [];
  parts.push("## INPUT ASSETS");
  parts.push("(아래 자산을 참고해서 답변/산출물을 생성하세요.)");

  for (const a of args.input_asset_payloads ?? []) {
    const header = `\n### [${safe(a.asset_type)}] ${safe(a.title)} (asset_id=${safe(a.asset_id)})`;
    parts.push(header);
    if (a.description) parts.push(`- description: ${safe(a.description)}`);
    if (a.tags?.length) parts.push(`- tags: ${a.tags.map(safe).join(", ")}`);

    const body = renderPayload(a, max_rows_per_table);
    if (body) parts.push(body);

    // 총 길이 컷
    if (parts.join("\n").length > max_chars_total) {
      parts.push("\n[TRUNCATED: input assets exceeded max_chars_total]");
      break;
    }
  }

  const out = parts.join("\n");
  if (out.length <= max_chars_total) return out;
  return out.slice(0, max_chars_total) + "\n[TRUNCATED]";
}

function renderPayload(a: InputAssetPayload, maxRows: number): string {
  const p = a?.payload;

  if (!p) return "";

  // table payload (클라 payloadFromBlock 기준)
  if (p.kind === "table") {
    const cols = Array.isArray(p.columns) ? p.columns : [];
    const rows = Array.isArray(p.rows) ? p.rows : [];
    const colKeys = cols.map((c: any) => pickString(c?.key) ?? pickString(c?.label) ?? "col").slice(0, 50);

    const take = rows.slice(0, maxRows);
    const lines: string[] = [];
    lines.push("```tsv");
    lines.push(colKeys.join("\t"));

    for (const r of take) {
      const rowObj = (r && typeof r === "object" && !Array.isArray(r)) ? r : {};
      const row = colKeys.map((k) => sanitizeCell(rowObj[k]));
      lines.push(row.join("\t"));
    }
    if (rows.length > take.length) lines.push(`[... ${rows.length - take.length} more rows truncated ...]`);
    lines.push("```");
    return lines.join("\n");
  }

  // code payload
  if (p.kind === "code") {
    const lang = pickString(p.language) ?? "";
    const text = pickString(p.text) ?? "";
    return ["```" + safe(lang), text, "```"].join("\n");
  }

  // document payload
  if (p.kind === "document") {
    const body = pickString(p.body) ?? "";
    if (!body) return "";
    return body.length > 8000 ? body.slice(0, 8000) + "\n[... truncated ...]" : body;
  }

  // fallback: json
  try {
    const json = JSON.stringify(p, null, 2);
    return ["```json", json, "```"].join("\n");
  } catch {
    return String(p);
  }
}

function sanitizeCell(v: any): string {
  if (v === null || v === undefined) return "";
  const s = typeof v === "string" ? v : String(v);
  // tsv 깨는 탭/개행 제거
  return s.replace(/\t/g, " ").replace(/\r?\n/g, " ").slice(0, 500);
}

function asStringArray(v: any): string[] | null {
  if (!Array.isArray(v)) return null;
  const out: string[] = [];
  for (const x of v) {
    if (typeof x === "string" && x.trim()) out.push(x);
  }
  return out;
}

function asAssetPayloadArray(v: any): InputAssetPayload[] {
  if (!Array.isArray(v)) return [];
  const out: InputAssetPayload[] = [];
  for (const x of v) {
    if (!isPlainObject(x)) continue;
    const asset_id = pickString(x.asset_id) ?? "";
    if (!asset_id) continue;

    out.push({
      asset_id,
      asset_type: pickString(x.asset_type) ?? "",
      title: pickString(x.title) ?? "",
      description: pickString(x.description) ?? "",
      created_at: pickString(x.created_at) ?? "",
      created_turn_id: pickString(x.created_turn_id) ?? "",
      payload: x.payload,
      tags: Array.isArray(x.tags) ? x.tags.filter((t: any) => typeof t === "string") : [],
      reusable: !!x.reusable,
    });
  }
  return out;
}

function uniqStrings(arr: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const s of arr) {
    const t = (s ?? "").trim();
    if (!t) continue;
    if (seen.has(t)) continue;
    seen.add(t);
    out.push(t);
  }
  return out;
}

function pickString(v: any): string | null {
  if (typeof v === "string" && v.trim().length > 0) return v;
  return null;
}

function isPlainObject(x: any): x is Record<string, any> {
  return !!x && typeof x === "object" && !Array.isArray(x);
}

function clampInt(n: number, lo: number, hi: number): number {
  const x = Math.floor(Number(n));
  if (!Number.isFinite(x)) return lo;
  if (x < lo) return lo;
  if (x > hi) return hi;
  return x;
}

function safe(s: any): string {
  return String(s ?? "").replace(/\r?\n/g, " ").trim();
}