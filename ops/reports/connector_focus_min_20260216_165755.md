# Connector Focus (Minimal)

- generated_at: 2026-02-16T16:57:55.8432540+09:00
- source_audit: C:\Users\User\Desktop\orchestra\ops\reports\connector_audit_20260216_164327.json
- scanned_top_files: 20

## Claude candidates

### Claude block 1
**ops\reports\connector_audit_20260216_163225.json**  (hit line: 2302)
-----
 2292:       "file": "_dump_ws_core.py.txt",
 2293:       "line": 285,
 2294:       "kind": "claude",
 2295:       "pattern": "anthropic",
 2296:       "text": "return _env(\"ANTHROPIC_API_KEY\") != \"\" and httpx is not None"
 2297:     },
 2298:     {
 2299:       "file": "_dump_ws_core.py.txt",
 2300:       "line": 292,
 2301:       "kind": "claude",
 2302:       "pattern": "claude-",
 2303:       "text": "return _env(\"ORCHESTRA_CLAUDE_MODEL\", \"claude-sonnet-4-5\")"
 2304:     },
 2305:     {
 2306:       "file": "_dump_ws_core.py.txt",
 2307:       "line": 295,
 2308:       "kind": "http",
 2309:       "pattern": "base_url",
 2310:       "text": "def _claude_base_url() -> str:"
 2311:     },
 2312:     {
 2313:       "file": "_dump_ws_core.py.txt",
 2314:       "line": 296,
 2315:       "kind": "claude",
 2316:       "pattern": "anthropic",
 2317:       "text": "base = _env(\"ANTHROPIC_BASE_URL\", \"https://api.anthropic.com\").rstrip(\"/\")"
 2318:     },
 2319:     {
 2320:       "file": "_dump_ws_core.py.txt",
-----

### Claude block 2
**ops\reports\connector_audit_20260216_163225.json**  (hit line: 2323)
-----
 2313:       "file": "_dump_ws_core.py.txt",
 2314:       "line": 296,
 2315:       "kind": "claude",
 2316:       "pattern": "anthropic",
 2317:       "text": "base = _env(\"ANTHROPIC_BASE_URL\", \"https://api.anthropic.com\").rstrip(\"/\")"
 2318:     },
 2319:     {
 2320:       "file": "_dump_ws_core.py.txt",
 2321:       "line": 296,
 2322:       "kind": "claude",
 2323:       "pattern": "api.anthropic.com",
 2324:       "text": "base = _env(\"ANTHROPIC_BASE_URL\", \"https://api.anthropic.com\").rstrip(\"/\")"
 2325:     },
 2326:     {
 2327:       "file": "_dump_ws_core.py.txt",
 2328:       "line": 296,
 2329:       "kind": "http",
 2330:       "pattern": "base_url",
 2331:       "text": "base = _env(\"ANTHROPIC_BASE_URL\", \"https://api.anthropic.com\").rstrip(\"/\")"
 2332:     },
 2333:     {
 2334:       "file": "_dump_ws_core.py.txt",
 2335:       "line": 316,
 2336:       "kind": "claude",
 2337:       "pattern": "anthropic",
 2338:       "text": "api_key = _env(\"ANTHROPIC_API_KEY\")"
 2339:     },
 2340:     {
 2341:       "file": "_dump_ws_core.py.txt",
-----

### Claude block 3
**ops\reports\connector_audit_20260216_163225.json**  (hit line: 2351)
-----
 2341:       "file": "_dump_ws_core.py.txt",
 2342:       "line": 337,
 2343:       "kind": "http",
 2344:       "pattern": "base_url",
 2345:       "text": "base = _claude_base_url()"
 2346:     },
 2347:     {
 2348:       "file": "_dump_ws_core.py.txt",
 2349:       "line": 338,
 2350:       "kind": "claude",
 2351:       "pattern": "/v1/messages",
 2352:       "text": "url = f\"{base}/v1/messages\""
 2353:     },
 2354:     {
 2355:       "file": "_dump_ws_core.py.txt",
 2356:       "line": 340,
 2357:       "kind": "claude",
 2358:       "pattern": "x-api-key",
 2359:       "text": "\"x-api-key\": api_key,"
 2360:     },
 2361:     {
 2362:       "file": "_dump_ws_core.py.txt",
 2363:       "line": 341,
 2364:       "kind": "claude",
 2365:       "pattern": "anthropic",
 2366:       "text": "\"anthropic-version\": _env(\"ANTHROPIC_VERSION\", \"2023-06-01\"),"
 2367:     },
 2368:     {
 2369:       "file": "_dump_ws_core.py.txt",
-----

### Claude block 4
**ops\reports\connector_audit_20260216_163225.json**  (hit line: 2372)
-----
 2362:       "file": "_dump_ws_core.py.txt",
 2363:       "line": 341,
 2364:       "kind": "claude",
 2365:       "pattern": "anthropic",
 2366:       "text": "\"anthropic-version\": _env(\"ANTHROPIC_VERSION\", \"2023-06-01\"),"
 2367:     },
 2368:     {
 2369:       "file": "_dump_ws_core.py.txt",
 2370:       "line": 341,
 2371:       "kind": "claude",
 2372:       "pattern": "anthropic-version",
 2373:       "text": "\"anthropic-version\": _env(\"ANTHROPIC_VERSION\", \"2023-06-01\"),"
 2374:     },
 2375:     {
 2376:       "file": "_dump_ws_core.py.txt",
 2377:       "line": 403,
 2378:       "kind": "claude",
 2379:       "pattern": "anthropic",
 2380:       "text": "return (\"claude\", \"(core stub:claude) ANTHROPIC_API_KEY 또는 httpx가 없어 비활성.\", False, meta)"
 2381:     },
 2382:     {
 2383:       "file": "_status_raw.json",
 2384:       "line": 34,
 2385:       "kind": "http",
 2386:       "pattern": "base_url",
 2387:       "text": "\"deepseek_base_url\": \"https://api.deepseek.com\","
 2388:     },
 2389:     {
 2390:       "file": "_status.json",
-----

### Claude block 5
**ops\reports\connector_audit_20260216_163225.md**  (hit line: 66)
-----
   56: - **gemini** "_dump_ws_core.py.txt:274" (pattern: $(@{file=_dump_ws_core.py.txt; line=274; kind=gemini; pattern=generativelanguage.googleapis.com; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"}.pattern))
   57:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
   58: - **gemini** "_dump_ws_core.py.txt:274" (pattern: $(@{file=_dump_ws_core.py.txt; line=274; kind=gemini; pattern=generateContent; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"}.pattern))
   59:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
   60: - **gemini** "_dump_ws_core.py.txt:274" (pattern: $(@{file=_dump_ws_core.py.txt; line=274; kind=gemini; pattern=models/; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"}.pattern))
   61:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
   62: - **gemini** "_dump_ws_core.py.txt:274" (pattern: $(@{file=_dump_ws_core.py.txt; line=274; kind=gemini; pattern=googleapis; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"}.pattern))
   63:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
   64: - **claude** "_dump_ws_core.py.txt:285" (pattern: $(@{file=_dump_ws_core.py.txt; line=285; kind=claude; pattern=anthropic; text=return _env("ANTHROPIC_API_KEY") != "" and httpx is not None}.pattern))
   65:   - return _env("ANTHROPIC_API_KEY") != "" and httpx is not None
   66: - **claude** "_dump_ws_core.py.txt:292" (pattern: $(@{file=_dump_ws_core.py.txt; line=292; kind=claude; pattern=claude-; text=return _env("ORCHESTRA_CLAUDE_MODEL", "claude-sonnet-4-5")}.pattern))
   67:   - return _env("ORCHESTRA_CLAUDE_MODEL", "claude-sonnet-4-5")
   68: - **http** "_dump_ws_core.py.txt:295" (pattern: $(@{file=_dump_ws_core.py.txt; line=295; kind=http; pattern=base_url; text=def _claude_base_url() -> str:}.pattern))
   69:   - def _claude_base_url() -> str:
   70: - **claude** "_dump_ws_core.py.txt:296" (pattern: $(@{file=_dump_ws_core.py.txt; line=296; kind=claude; pattern=anthropic; text=base = _env("ANTHROPIC_BASE_URL", "https://api.anthropic.com").rstrip("/")}.pattern))
   71:   - base = _env("ANTHROPIC_BASE_URL", "https://api.anthropic.com").rstrip("/")
   72: - **claude** "_dump_ws_core.py.txt:296" (pattern: $(@{file=_dump_ws_core.py.txt; line=296; kind=claude; pattern=api.anthropic.com; text=base = _env("ANTHROPIC_BASE_URL", "https://api.anthropic.com").rstrip("/")}.pattern))
   73:   - base = _env("ANTHROPIC_BASE_URL", "https://api.anthropic.com").rstrip("/")
   74: - **http** "_dump_ws_core.py.txt:296" (pattern: $(@{file=_dump_ws_core.py.txt; line=296; kind=http; pattern=base_url; text=base = _env("ANTHROPIC_BASE_URL", "https://api.anthropic.com").rstrip("/")}.pattern))
   75:   - base = _env("ANTHROPIC_BASE_URL", "https://api.anthropic.com").rstrip("/")
   76: - **claude** "_dump_ws_core.py.txt:316" (pattern: $(@{file=_dump_ws_core.py.txt; line=316; kind=claude; pattern=anthropic; text=api_key = _env("ANTHROPIC_API_KEY")}.pattern))
   77:   - api_key = _env("ANTHROPIC_API_KEY")
   78: - **http** "_dump_ws_core.py.txt:337" (pattern: $(@{file=_dump_ws_core.py.txt; line=337; kind=http; pattern=base_url; text=base = _claude_base_url()}.pattern))
   79:   - base = _claude_base_url()
   80: - **claude** "_dump_ws_core.py.txt:338" (pattern: $(@{file=_dump_ws_core.py.txt; line=338; kind=claude; pattern=/v1/messages; text=url = f"{base}/v1/messages"}.pattern))
   81:   - url = f"{base}/v1/messages"
   82: - **claude** "_dump_ws_core.py.txt:340" (pattern: $(@{file=_dump_ws_core.py.txt; line=340; kind=claude; pattern=x-api-key; text="x-api-key": api_key,}.pattern))
   83:   - "x-api-key": api_key,
   84: - **claude** "_dump_ws_core.py.txt:341" (pattern: $(@{file=_dump_ws_core.py.txt; line=341; kind=claude; pattern=anthropic; text="anthropic-version": _env("ANTHROPIC_VERSION", "2023-06-01"),}.pattern))
-----

### Claude block 6
**ops\reports\connector_audit_20260216_163225.md**  (hit line: 85)
-----
   75:   - base = _env("ANTHROPIC_BASE_URL", "https://api.anthropic.com").rstrip("/")
   76: - **claude** "_dump_ws_core.py.txt:316" (pattern: $(@{file=_dump_ws_core.py.txt; line=316; kind=claude; pattern=anthropic; text=api_key = _env("ANTHROPIC_API_KEY")}.pattern))
   77:   - api_key = _env("ANTHROPIC_API_KEY")
   78: - **http** "_dump_ws_core.py.txt:337" (pattern: $(@{file=_dump_ws_core.py.txt; line=337; kind=http; pattern=base_url; text=base = _claude_base_url()}.pattern))
   79:   - base = _claude_base_url()
   80: - **claude** "_dump_ws_core.py.txt:338" (pattern: $(@{file=_dump_ws_core.py.txt; line=338; kind=claude; pattern=/v1/messages; text=url = f"{base}/v1/messages"}.pattern))
   81:   - url = f"{base}/v1/messages"
   82: - **claude** "_dump_ws_core.py.txt:340" (pattern: $(@{file=_dump_ws_core.py.txt; line=340; kind=claude; pattern=x-api-key; text="x-api-key": api_key,}.pattern))
   83:   - "x-api-key": api_key,
   84: - **claude** "_dump_ws_core.py.txt:341" (pattern: $(@{file=_dump_ws_core.py.txt; line=341; kind=claude; pattern=anthropic; text="anthropic-version": _env("ANTHROPIC_VERSION", "2023-06-01"),}.pattern))
   85:   - "anthropic-version": _env("ANTHROPIC_VERSION", "2023-06-01"),
   86: - **claude** "_dump_ws_core.py.txt:341" (pattern: $(@{file=_dump_ws_core.py.txt; line=341; kind=claude; pattern=anthropic-version; text="anthropic-version": _env("ANTHROPIC_VERSION", "2023-06-01"),}.pattern))
   87:   - "anthropic-version": _env("ANTHROPIC_VERSION", "2023-06-01"),
   88: - **claude** "_dump_ws_core.py.txt:403" (pattern: $(@{file=_dump_ws_core.py.txt; line=403; kind=claude; pattern=anthropic; text=return ("claude", "(core stub:claude) ANTHROPIC_API_KEY 또는 httpx가 없어 비활성.", False, meta)}.pattern))
   89:   - return ("claude", "(core stub:claude) ANTHROPIC_API_KEY 또는 httpx가 없어 비활성.", False, meta)
   90: - **http** "_status_raw.json:34" (pattern: $(@{file=_status_raw.json; line=34; kind=http; pattern=base_url; text="deepseek_base_url": "https://api.deepseek.com",}.pattern))
   91:   - "deepseek_base_url": "https://api.deepseek.com",
   92: - **http** "_status.json:34" (pattern: $(@{file=_status.json; line=34; kind=http; pattern=base_url; text="deepseek_base_url": "https://api.deepseek.com",}.pattern))
   93:   - "deepseek_base_url": "https://api.deepseek.com",
   94: - **http** "core_prompt_dump_min.txt:290" (pattern: $(@{file=core_prompt_dump_min.txt; line=290; kind=http; pattern=404; text=raise HTTPException(status_code=404, detail="Not Found")}.pattern))
   95:   - raise HTTPException(status_code=404, detail="Not Found")
   96: - **http** "core_prompt_dump_min.txt:312" (pattern: $(@{file=core_prompt_dump_min.txt; line=312; kind=http; pattern=404; text=raise HTTPException(status_code=404, detail="Not Found")}.pattern))
   97:   - raise HTTPException(status_code=404, detail="Not Found")
   98: - **http** "core_prompt_dump_min.txt:324" (pattern: $(@{file=core_prompt_dump_min.txt; line=324; kind=http; pattern=404; text=raise HTTPException(status_code=404, detail="Not Found")}.pattern))
   99:   - raise HTTPException(status_code=404, detail="Not Found")
  100: - **http** "core_prompt_dump_min.txt:562" (pattern: $(@{file=core_prompt_dump_min.txt; line=562; kind=http; pattern=endpoint; text=# - endpoints:}.pattern))
  101:   - # - endpoints:
  102: - **http** "core_prompt_dump_min.txt:564" (pattern: $(@{file=core_prompt_dump_min.txt; line=564; kind=http; pattern=endpoint; text=#     POST /api/chat : UI single endpoint (minimal schema-compatible response)}.pattern))
  103:   - #     POST /api/chat : UI single endpoint (minimal schema-compatible response)
-----

### Claude block 7
**ops\reports\connector_audit_20260216_163225.md**  (hit line: 120)
-----
  110: - **http** "core_prompt_dump_min.txt:656" (pattern: $(@{file=core_prompt_dump_min.txt; line=656; kind=http; pattern=Bearer ; text="Authorization": f"Bearer {OPENAI_API_KEY}",}.pattern))
  111:   - "Authorization": f"Bearer {OPENAI_API_KEY}",
  112: - **http** "core_prompt_dump_min.txt:797" (pattern: $(@{file=core_prompt_dump_min.txt; line=797; kind=http; pattern=http_status; text=for attr in ("status_code", "http_status", "status"):}.pattern))
  113:   - for attr in ("status_code", "http_status", "status"):
  114: - **http** "core_prompt_dump_min.txt:990" (pattern: $(@{file=core_prompt_dump_min.txt; line=990; kind=http; pattern=404; text=if status in (400, 404, 409, 422):}.pattern))
  115:   - if status in (400, 404, 409, 422):
  116: - **claude** "core_prompt_dump_min.txt:2203" (pattern: $(@{file=core_prompt_dump_min.txt; line=2203; kind=claude; pattern=anthropic; text="ANTHROPIC_API_KEY": present("ANTHROPIC_API_KEY"),}.pattern))
  117:   - "ANTHROPIC_API_KEY": present("ANTHROPIC_API_KEY"),
  118: - **gemini** "core_prompt_dump_min.txt:2289" (pattern: $(@{file=core_prompt_dump_min.txt; line=2289; kind=gemini; pattern=gemini-; text=gemini_model = "gemini-2.5-flash"}.pattern))
  119:   - gemini_model = "gemini-2.5-flash"
  120: - **claude** "core_prompt_dump_min.txt:2290" (pattern: $(@{file=core_prompt_dump_min.txt; line=2290; kind=claude; pattern=claude-; text=claude_model = "claude-3-5-sonnet-20241022"}.pattern))
  121:   - claude_model = "claude-3-5-sonnet-20241022"
  122: - **gemini** "core_prompt_dump_min.txt:2327" (pattern: $(@{file=core_prompt_dump_min.txt; line=2327; kind=gemini; pattern=gemini-; text=gemini_model = "gemini-2.5-flash"}.pattern))
  123:   - gemini_model = "gemini-2.5-flash"
  124: - **claude** "core_prompt_dump_min.txt:2328" (pattern: $(@{file=core_prompt_dump_min.txt; line=2328; kind=claude; pattern=claude-; text=claude_model = "claude-3-5-sonnet-20241022"}.pattern))
  125:   - claude_model = "claude-3-5-sonnet-20241022"
  126: - **http** "core_prompt_dump_min.txt:2581" (pattern: $(@{file=core_prompt_dump_min.txt; line=2581; kind=http; pattern=Authorization; text=headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}}.pattern))
  127:   - headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
  128: - **http** "core_prompt_dump_min.txt:2581" (pattern: $(@{file=core_prompt_dump_min.txt; line=2581; kind=http; pattern=Bearer ; text=headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}}.pattern))
  129:   - headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
  130: - **http** "core_prompt_dump_min.txt:2612" (pattern: $(@{file=core_prompt_dump_min.txt; line=2612; kind=http; pattern=Authorization; text=headers = {"Authorization": f"Bearer {api_key}"}}.pattern))
  131:   - headers = {"Authorization": f"Bearer {api_key}"}
  132: - **http** "core_prompt_dump_min.txt:2612" (pattern: $(@{file=core_prompt_dump_min.txt; line=2612; kind=http; pattern=Bearer ; text=headers = {"Authorization": f"Bearer {api_key}"}}.pattern))
  133:   - headers = {"Authorization": f"Bearer {api_key}"}
  134: - **http** "core_prompt_dump_min.txt:2662" (pattern: $(@{file=core_prompt_dump_min.txt; line=2662; kind=http; pattern=base_url; text=self.base_url = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")}.pattern))
  135:   - self.base_url = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")
  136: - **http** "core_prompt_dump_min.txt:2671" (pattern: $(@{file=core_prompt_dump_min.txt; line=2671; kind=http; pattern=Authorization; text="Authorization": f"Bearer {self.api_key}",}.pattern))
  137:   - "Authorization": f"Bearer {self.api_key}",
  138: - **http** "core_prompt_dump_min.txt:2671" (pattern: $(@{file=core_prompt_dump_min.txt; line=2671; kind=http; pattern=Bearer ; text="Authorization": f"Bearer {self.api_key}",}.pattern))
-----

### Claude block 8
**ops\reports\connector_audit_20260216_163225.md**  (hit line: 180)
-----
  170: - **http** "core_prompt_dump.txt:1419" (pattern: $(@{file=core_prompt_dump.txt; line=1419; kind=http; pattern=Bearer ; text="Authorization": f"Bearer {OPENAI_API_KEY}",}.pattern))
  171:   - "Authorization": f"Bearer {OPENAI_API_KEY}",
  172: - **http** "core_prompt_dump.txt:1560" (pattern: $(@{file=core_prompt_dump.txt; line=1560; kind=http; pattern=http_status; text=for attr in ("status_code", "http_status", "status"):}.pattern))
  173:   - for attr in ("status_code", "http_status", "status"):
  174: - **http** "core_prompt_dump.txt:1753" (pattern: $(@{file=core_prompt_dump.txt; line=1753; kind=http; pattern=404; text=if status in (400, 404, 409, 422):}.pattern))
  175:   - if status in (400, 404, 409, 422):
  176: - **claude** "core_prompt_dump.txt:2966" (pattern: $(@{file=core_prompt_dump.txt; line=2966; kind=claude; pattern=anthropic; text="ANTHROPIC_API_KEY": present("ANTHROPIC_API_KEY"),}.pattern))
  177:   - "ANTHROPIC_API_KEY": present("ANTHROPIC_API_KEY"),
  178: - **gemini** "core_prompt_dump.txt:3052" (pattern: $(@{file=core_prompt_dump.txt; line=3052; kind=gemini; pattern=gemini-; text=gemini_model = "gemini-2.5-flash"}.pattern))
  179:   - gemini_model = "gemini-2.5-flash"
  180: - **claude** "core_prompt_dump.txt:3053" (pattern: $(@{file=core_prompt_dump.txt; line=3053; kind=claude; pattern=claude-; text=claude_model = "claude-3-5-sonnet-20241022"}.pattern))
  181:   - claude_model = "claude-3-5-sonnet-20241022"
  182: - **gemini** "core_prompt_dump.txt:3090" (pattern: $(@{file=core_prompt_dump.txt; line=3090; kind=gemini; pattern=gemini-; text=gemini_model = "gemini-2.5-flash"}.pattern))
  183:   - gemini_model = "gemini-2.5-flash"
  184: - **claude** "core_prompt_dump.txt:3091" (pattern: $(@{file=core_prompt_dump.txt; line=3091; kind=claude; pattern=claude-; text=claude_model = "claude-3-5-sonnet-20241022"}.pattern))
  185:   - claude_model = "claude-3-5-sonnet-20241022"
  186: - **gemini** "core_prompt_dump.txt:3339" (pattern: $(@{file=core_prompt_dump.txt; line=3339; kind=gemini; pattern=generativelanguage.googleapis.com; text=Google Gemini API (generativelanguage.googleapis.com) 호출 최소 구현.}.pattern))
  187:   - Google Gemini API (generativelanguage.googleapis.com) 호출 최소 구현.
  188: - **gemini** "core_prompt_dump.txt:3339" (pattern: $(@{file=core_prompt_dump.txt; line=3339; kind=gemini; pattern=googleapis; text=Google Gemini API (generativelanguage.googleapis.com) 호출 최소 구현.}.pattern))
  189:   - Google Gemini API (generativelanguage.googleapis.com) 호출 최소 구현.
  190: - **gemini** "core_prompt_dump.txt:3343" (pattern: $(@{file=core_prompt_dump.txt; line=3343; kind=gemini; pattern=gemini-; text=- ORCHESTRA_GEMINI_MODEL (없으면 GEMINI_MODEL, 그마저 없으면 gemini-2.0-flash)}.pattern))
  191:   - - ORCHESTRA_GEMINI_MODEL (없으면 GEMINI_MODEL, 그마저 없으면 gemini-2.0-flash)
  192: - **gemini** "core_prompt_dump.txt:3357" (pattern: $(@{file=core_prompt_dump.txt; line=3357; kind=gemini; pattern=gemini-; text=self.model = (os.getenv("ORCHESTRA_GEMINI_MODEL") or os.getenv("GEMINI_MODEL") or "gemini-2.0-flash").strip()}.pattern))
  193:   - self.model = (os.getenv("ORCHESTRA_GEMINI_MODEL") or os.getenv("GEMINI_MODEL") or "gemini-2.0-flash").strip()
  194: - **gemini** "core_prompt_dump.txt:3386" (pattern: $(@{file=core_prompt_dump.txt; line=3386; kind=gemini; pattern=generativelanguage.googleapis.com; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"}.pattern))
  195:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"
  196: - **gemini** "core_prompt_dump.txt:3386" (pattern: $(@{file=core_prompt_dump.txt; line=3386; kind=gemini; pattern=generateContent; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"}.pattern))
  197:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"
  198: - **gemini** "core_prompt_dump.txt:3386" (pattern: $(@{file=core_prompt_dump.txt; line=3386; kind=gemini; pattern=models/; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"}.pattern))
-----

### Claude block 9
**orchestra__backup_20260213_214212\orchestra__backup_20260213_214212\core_prompt_dump.txt**  (hit line: 3053)
-----
 3043:     mode: str = Form("fact"),
 3044:     question: str = Form(""),
 3045:     files: List[UploadFile] = File(default=[]),
 3046: ):
 3047:     q = (question or "").strip()
 3048:     if not q:
 3049:         return {"ok": False, "error": "question is required"}
 3050: 
 3051:     m = (mode or "fact").strip().lower()
 3052:     gemini_model = "gemini-2.5-flash"
 3053:     claude_model = "claude-3-5-sonnet-20241022"
 3054:     pplx_model = "sonar"
 3055: 
 3056:     docs, imgs, errors = await extract_files(files or [])
 3057:     docs2 = await summarize_docs_if_needed(docs, claude_model=claude_model)
 3058:     image_summaries = await summarize_images_with_gemini(imgs, gemini_model=gemini_model) if imgs else []
 3059: 
 3060:     file_ctx = build_file_context(docs2, image_summaries=image_summaries)
 3061:     full_q = q + (("\n\n[업로드 파일 내용]\n" + file_ctx) if file_ctx else "")
 3062: 
 3063:     if m == "fact":
 3064:         r = await ask_gemini(_wrap_user_question("fact", full_q), model=gemini_model)
 3065:         r.pop("raw", None); r["provider"] = "gemini"
 3066:         return {"ok": True, "mode": m, "question": q, "files": {"docs": len(docs2), "images": len(imgs), "errors": errors}, "result": r}
 3067: 
 3068:     if m == "code":
 3069:         r = await ask_claude(_wrap_user_question("code", full_q), model=claude_model)
 3070:         r.pop("raw", None); r["provider"] = "claude"
 3071:         return {"ok": True, "mode": m, "question": q, "files": {"docs": len(docs2), "images": len(imgs), "errors": errors}, "result": r}
-----

### Claude block 10
**orchestra__backup_20260213_214212\orchestra__backup_20260213_214212\core_prompt_dump.txt**  (hit line: 3091)
-----
 3081: @app.post("/ask_upload/merge")
 3082: async def ask_upload_merge(
 3083:     question: str = Form(""),
 3084:     files: List[UploadFile] = File(default=[]),
 3085: ):
 3086:     q = (question or "").strip()
 3087:     if not q:
 3088:         return {"ok": False, "error": "question is required"}
 3089: 
 3090:     gemini_model = "gemini-2.5-flash"
 3091:     claude_model = "claude-3-5-sonnet-20241022"
 3092:     pplx_model = "sonar"
 3093: 
 3094:     docs, imgs, errors = await extract_files(files or [])
 3095:     docs2 = await summarize_docs_if_needed(docs, claude_model=claude_model)
 3096:     image_summaries = await summarize_images_with_gemini(imgs, gemini_model=gemini_model) if imgs else []
 3097: 
 3098:     file_ctx = build_file_context(docs2, image_summaries=image_summaries)
 3099:     full_q = q + (("\n\n[업로드 파일 내용]\n" + file_ctx) if file_ctx else "")
 3100: 
 3101:     g, c, p = await asyncio.gather(
 3102:         ask_gemini(_wrap_user_question("fact", full_q), model=gemini_model),
 3103:         ask_claude(_wrap_user_question("code", full_q), model=claude_model),
 3104:         ask_perplexity(_wrap_user_question("research", full_q), model=pplx_model),
 3105:     )
 3106: 
 3107:     gtxt = g.get("text", "") if isinstance(g, dict) else ""
 3108:     ctxt = c.get("text", "") if isinstance(c, dict) else ""
 3109:     ptxt = p.get("text", "") if isinstance(p, dict) else ""
-----

### Claude block 11
**orchestra__backup_20260213_214212\orchestra__backup_20260213_214212\orchestra__backup_20260213_214212\orchestra__backup_20260213_214212\orchestra__backup_20260213_214212\core_prompt_dump.txt**  (hit line: 3053)
-----
 3043:     mode: str = Form("fact"),
 3044:     question: str = Form(""),
 3045:     files: List[UploadFile] = File(default=[]),
 3046: ):
 3047:     q = (question or "").strip()
 3048:     if not q:
 3049:         return {"ok": False, "error": "question is required"}
 3050: 
 3051:     m = (mode or "fact").strip().lower()
 3052:     gemini_model = "gemini-2.5-flash"
 3053:     claude_model = "claude-3-5-sonnet-20241022"
 3054:     pplx_model = "sonar"
 3055: 
 3056:     docs, imgs, errors = await extract_files(files or [])
 3057:     docs2 = await summarize_docs_if_needed(docs, claude_model=claude_model)
 3058:     image_summaries = await summarize_images_with_gemini(imgs, gemini_model=gemini_model) if imgs else []
 3059: 
 3060:     file_ctx = build_file_context(docs2, image_summaries=image_summaries)
 3061:     full_q = q + (("\n\n[업로드 파일 내용]\n" + file_ctx) if file_ctx else "")
 3062: 
 3063:     if m == "fact":
 3064:         r = await ask_gemini(_wrap_user_question("fact", full_q), model=gemini_model)
 3065:         r.pop("raw", None); r["provider"] = "gemini"
 3066:         return {"ok": True, "mode": m, "question": q, "files": {"docs": len(docs2), "images": len(imgs), "errors": errors}, "result": r}
 3067: 
 3068:     if m == "code":
 3069:         r = await ask_claude(_wrap_user_question("code", full_q), model=claude_model)
 3070:         r.pop("raw", None); r["provider"] = "claude"
 3071:         return {"ok": True, "mode": m, "question": q, "files": {"docs": len(docs2), "images": len(imgs), "errors": errors}, "result": r}
-----

### Claude block 12
**orchestra__backup_20260213_214212\orchestra__backup_20260213_214212\orchestra__backup_20260213_214212\orchestra__backup_20260213_214212\orchestra__backup_20260213_214212\core_prompt_dump.txt**  (hit line: 3091)
-----
 3081: @app.post("/ask_upload/merge")
 3082: async def ask_upload_merge(
 3083:     question: str = Form(""),
 3084:     files: List[UploadFile] = File(default=[]),
 3085: ):
 3086:     q = (question or "").strip()
 3087:     if not q:
 3088:         return {"ok": False, "error": "question is required"}
 3089: 
 3090:     gemini_model = "gemini-2.5-flash"
 3091:     claude_model = "claude-3-5-sonnet-20241022"
 3092:     pplx_model = "sonar"
 3093: 
 3094:     docs, imgs, errors = await extract_files(files or [])
 3095:     docs2 = await summarize_docs_if_needed(docs, claude_model=claude_model)
 3096:     image_summaries = await summarize_images_with_gemini(imgs, gemini_model=gemini_model) if imgs else []
 3097: 
 3098:     file_ctx = build_file_context(docs2, image_summaries=image_summaries)
 3099:     full_q = q + (("\n\n[업로드 파일 내용]\n" + file_ctx) if file_ctx else "")
 3100: 
 3101:     g, c, p = await asyncio.gather(
 3102:         ask_gemini(_wrap_user_question("fact", full_q), model=gemini_model),
 3103:         ask_claude(_wrap_user_question("code", full_q), model=claude_model),
 3104:         ask_perplexity(_wrap_user_question("research", full_q), model=pplx_model),
 3105:     )
 3106: 
 3107:     gtxt = g.get("text", "") if isinstance(g, dict) else ""
 3108:     ctxt = c.get("text", "") if isinstance(c, dict) else ""
 3109:     ptxt = p.get("text", "") if isinstance(p, dict) else ""
-----

## Gemini candidates

### Gemini block 1
**ops\reports\connector_audit_20260216_163225.json**  (hit line: 2260)
-----
 2250:       "file": "_dump_ws_core.py.txt",
 2251:       "line": 203,
 2252:       "kind": "http",
 2253:       "pattern": "Bearer ",
 2254:       "text": "headers = {\"Authorization\": f\"Bearer {api_key}\", \"Content-Type\": \"application/json; charset=utf-8\"}"
 2255:     },
 2256:     {
 2257:       "file": "_dump_ws_core.py.txt",
 2258:       "line": 226,
 2259:       "kind": "gemini",
 2260:       "pattern": "gemini-",
 2261:       "text": "return _env(\"ORCHESTRA_GEMINI_MODEL\", \"gemini-2.0-flash\")"
 2262:     },
 2263:     {
 2264:       "file": "_dump_ws_core.py.txt",
 2265:       "line": 274,
 2266:       "kind": "gemini",
 2267:       "pattern": "generativelanguage.googleapis.com",
 2268:       "text": "url = f\"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}\""
 2269:     },
 2270:     {
 2271:       "file": "_dump_ws_core.py.txt",
 2272:       "line": 274,
 2273:       "kind": "gemini",
 2274:       "pattern": "generateContent",
 2275:       "text": "url = f\"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}\""
 2276:     },
 2277:     {
 2278:       "file": "_dump_ws_core.py.txt",
-----

### Gemini block 2
**ops\reports\connector_audit_20260216_163225.json**  (hit line: 2281)
-----
 2271:       "file": "_dump_ws_core.py.txt",
 2272:       "line": 274,
 2273:       "kind": "gemini",
 2274:       "pattern": "generateContent",
 2275:       "text": "url = f\"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}\""
 2276:     },
 2277:     {
 2278:       "file": "_dump_ws_core.py.txt",
 2279:       "line": 274,
 2280:       "kind": "gemini",
 2281:       "pattern": "models/",
 2282:       "text": "url = f\"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}\""
 2283:     },
 2284:     {
 2285:       "file": "_dump_ws_core.py.txt",
 2286:       "line": 274,
 2287:       "kind": "gemini",
 2288:       "pattern": "googleapis",
 2289:       "text": "url = f\"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}\""
 2290:     },
 2291:     {
 2292:       "file": "_dump_ws_core.py.txt",
 2293:       "line": 285,
 2294:       "kind": "claude",
 2295:       "pattern": "anthropic",
 2296:       "text": "return _env(\"ANTHROPIC_API_KEY\") != \"\" and httpx is not None"
 2297:     },
 2298:     {
 2299:       "file": "_dump_ws_core.py.txt",
-----

### Gemini block 3
**ops\reports\connector_audit_20260216_163225.json**  (hit line: 2484)
-----
 2474:       "file": "core_prompt_dump_min.txt",
 2475:       "line": 2203,
 2476:       "kind": "claude",
 2477:       "pattern": "anthropic",
 2478:       "text": "\"ANTHROPIC_API_KEY\": present(\"ANTHROPIC_API_KEY\"),"
 2479:     },
 2480:     {
 2481:       "file": "core_prompt_dump_min.txt",
 2482:       "line": 2289,
 2483:       "kind": "gemini",
 2484:       "pattern": "gemini-",
 2485:       "text": "gemini_model = \"gemini-2.5-flash\""
 2486:     },
 2487:     {
 2488:       "file": "core_prompt_dump_min.txt",
 2489:       "line": 2290,
 2490:       "kind": "claude",
 2491:       "pattern": "claude-",
 2492:       "text": "claude_model = \"claude-3-5-sonnet-20241022\""
 2493:     },
 2494:     {
 2495:       "file": "core_prompt_dump_min.txt",
 2496:       "line": 2327,
 2497:       "kind": "gemini",
 2498:       "pattern": "gemini-",
 2499:       "text": "gemini_model = \"gemini-2.5-flash\""
 2500:     },
 2501:     {
 2502:       "file": "core_prompt_dump_min.txt",
-----

### Gemini block 4
**ops\reports\connector_audit_20260216_163225.json**  (hit line: 2694)
-----
 2684:       "file": "core_prompt_dump.txt",
 2685:       "line": 2966,
 2686:       "kind": "claude",
 2687:       "pattern": "anthropic",
 2688:       "text": "\"ANTHROPIC_API_KEY\": present(\"ANTHROPIC_API_KEY\"),"
 2689:     },
 2690:     {
 2691:       "file": "core_prompt_dump.txt",
 2692:       "line": 3052,
 2693:       "kind": "gemini",
 2694:       "pattern": "gemini-",
 2695:       "text": "gemini_model = \"gemini-2.5-flash\""
 2696:     },
 2697:     {
 2698:       "file": "core_prompt_dump.txt",
 2699:       "line": 3053,
 2700:       "kind": "claude",
 2701:       "pattern": "claude-",
 2702:       "text": "claude_model = \"claude-3-5-sonnet-20241022\""
 2703:     },
 2704:     {
 2705:       "file": "core_prompt_dump.txt",
 2706:       "line": 3090,
 2707:       "kind": "gemini",
 2708:       "pattern": "gemini-",
 2709:       "text": "gemini_model = \"gemini-2.5-flash\""
 2710:     },
 2711:     {
 2712:       "file": "core_prompt_dump.txt",
-----

### Gemini block 5
**ops\reports\connector_audit_20260216_163225.md**  (hit line: 54)
-----
   44: - **http** "_dump_summary_injection.txt:16" (pattern: $(@{file=_dump_summary_injection.txt; line=16; kind=http; pattern=endpoint; text==== 2) ENDPOINT SMOKE: /healthz, /api/thread/summary/save, /api/pins/list ===}.pattern))
   45:   - === 2) ENDPOINT SMOKE: /healthz, /api/thread/summary/save, /api/pins/list ===
   46: - **http** "_dump_ws_core.py.txt:162" (pattern: $(@{file=_dump_ws_core.py.txt; line=162; kind=http; pattern=Authorization; text=headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json; charset=utf-8"}}.pattern))
   47:   - headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json; charset=utf-8"}
   48: - **http** "_dump_ws_core.py.txt:162" (pattern: $(@{file=_dump_ws_core.py.txt; line=162; kind=http; pattern=Bearer ; text=headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json; charset=utf-8"}}.pattern))
   49:   - headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json; charset=utf-8"}
   50: - **http** "_dump_ws_core.py.txt:203" (pattern: $(@{file=_dump_ws_core.py.txt; line=203; kind=http; pattern=Authorization; text=headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json; charset=utf-8"}}.pattern))
   51:   - headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json; charset=utf-8"}
   52: - **http** "_dump_ws_core.py.txt:203" (pattern: $(@{file=_dump_ws_core.py.txt; line=203; kind=http; pattern=Bearer ; text=headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json; charset=utf-8"}}.pattern))
   53:   - headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json; charset=utf-8"}
   54: - **gemini** "_dump_ws_core.py.txt:226" (pattern: $(@{file=_dump_ws_core.py.txt; line=226; kind=gemini; pattern=gemini-; text=return _env("ORCHESTRA_GEMINI_MODEL", "gemini-2.0-flash")}.pattern))
   55:   - return _env("ORCHESTRA_GEMINI_MODEL", "gemini-2.0-flash")
   56: - **gemini** "_dump_ws_core.py.txt:274" (pattern: $(@{file=_dump_ws_core.py.txt; line=274; kind=gemini; pattern=generativelanguage.googleapis.com; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"}.pattern))
   57:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
   58: - **gemini** "_dump_ws_core.py.txt:274" (pattern: $(@{file=_dump_ws_core.py.txt; line=274; kind=gemini; pattern=generateContent; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"}.pattern))
   59:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
   60: - **gemini** "_dump_ws_core.py.txt:274" (pattern: $(@{file=_dump_ws_core.py.txt; line=274; kind=gemini; pattern=models/; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"}.pattern))
   61:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
   62: - **gemini** "_dump_ws_core.py.txt:274" (pattern: $(@{file=_dump_ws_core.py.txt; line=274; kind=gemini; pattern=googleapis; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"}.pattern))
   63:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
   64: - **claude** "_dump_ws_core.py.txt:285" (pattern: $(@{file=_dump_ws_core.py.txt; line=285; kind=claude; pattern=anthropic; text=return _env("ANTHROPIC_API_KEY") != "" and httpx is not None}.pattern))
   65:   - return _env("ANTHROPIC_API_KEY") != "" and httpx is not None
   66: - **claude** "_dump_ws_core.py.txt:292" (pattern: $(@{file=_dump_ws_core.py.txt; line=292; kind=claude; pattern=claude-; text=return _env("ORCHESTRA_CLAUDE_MODEL", "claude-sonnet-4-5")}.pattern))
   67:   - return _env("ORCHESTRA_CLAUDE_MODEL", "claude-sonnet-4-5")
   68: - **http** "_dump_ws_core.py.txt:295" (pattern: $(@{file=_dump_ws_core.py.txt; line=295; kind=http; pattern=base_url; text=def _claude_base_url() -> str:}.pattern))
   69:   - def _claude_base_url() -> str:
   70: - **claude** "_dump_ws_core.py.txt:296" (pattern: $(@{file=_dump_ws_core.py.txt; line=296; kind=claude; pattern=anthropic; text=base = _env("ANTHROPIC_BASE_URL", "https://api.anthropic.com").rstrip("/")}.pattern))
   71:   - base = _env("ANTHROPIC_BASE_URL", "https://api.anthropic.com").rstrip("/")
   72: - **claude** "_dump_ws_core.py.txt:296" (pattern: $(@{file=_dump_ws_core.py.txt; line=296; kind=claude; pattern=api.anthropic.com; text=base = _env("ANTHROPIC_BASE_URL", "https://api.anthropic.com").rstrip("/")}.pattern))
-----

### Gemini block 6
**ops\reports\connector_audit_20260216_163225.md**  (hit line: 118)
-----
  108: - **http** "core_prompt_dump_min.txt:656" (pattern: $(@{file=core_prompt_dump_min.txt; line=656; kind=http; pattern=Authorization; text="Authorization": f"Bearer {OPENAI_API_KEY}",}.pattern))
  109:   - "Authorization": f"Bearer {OPENAI_API_KEY}",
  110: - **http** "core_prompt_dump_min.txt:656" (pattern: $(@{file=core_prompt_dump_min.txt; line=656; kind=http; pattern=Bearer ; text="Authorization": f"Bearer {OPENAI_API_KEY}",}.pattern))
  111:   - "Authorization": f"Bearer {OPENAI_API_KEY}",
  112: - **http** "core_prompt_dump_min.txt:797" (pattern: $(@{file=core_prompt_dump_min.txt; line=797; kind=http; pattern=http_status; text=for attr in ("status_code", "http_status", "status"):}.pattern))
  113:   - for attr in ("status_code", "http_status", "status"):
  114: - **http** "core_prompt_dump_min.txt:990" (pattern: $(@{file=core_prompt_dump_min.txt; line=990; kind=http; pattern=404; text=if status in (400, 404, 409, 422):}.pattern))
  115:   - if status in (400, 404, 409, 422):
  116: - **claude** "core_prompt_dump_min.txt:2203" (pattern: $(@{file=core_prompt_dump_min.txt; line=2203; kind=claude; pattern=anthropic; text="ANTHROPIC_API_KEY": present("ANTHROPIC_API_KEY"),}.pattern))
  117:   - "ANTHROPIC_API_KEY": present("ANTHROPIC_API_KEY"),
  118: - **gemini** "core_prompt_dump_min.txt:2289" (pattern: $(@{file=core_prompt_dump_min.txt; line=2289; kind=gemini; pattern=gemini-; text=gemini_model = "gemini-2.5-flash"}.pattern))
  119:   - gemini_model = "gemini-2.5-flash"
  120: - **claude** "core_prompt_dump_min.txt:2290" (pattern: $(@{file=core_prompt_dump_min.txt; line=2290; kind=claude; pattern=claude-; text=claude_model = "claude-3-5-sonnet-20241022"}.pattern))
  121:   - claude_model = "claude-3-5-sonnet-20241022"
  122: - **gemini** "core_prompt_dump_min.txt:2327" (pattern: $(@{file=core_prompt_dump_min.txt; line=2327; kind=gemini; pattern=gemini-; text=gemini_model = "gemini-2.5-flash"}.pattern))
  123:   - gemini_model = "gemini-2.5-flash"
  124: - **claude** "core_prompt_dump_min.txt:2328" (pattern: $(@{file=core_prompt_dump_min.txt; line=2328; kind=claude; pattern=claude-; text=claude_model = "claude-3-5-sonnet-20241022"}.pattern))
  125:   - claude_model = "claude-3-5-sonnet-20241022"
  126: - **http** "core_prompt_dump_min.txt:2581" (pattern: $(@{file=core_prompt_dump_min.txt; line=2581; kind=http; pattern=Authorization; text=headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}}.pattern))
  127:   - headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
  128: - **http** "core_prompt_dump_min.txt:2581" (pattern: $(@{file=core_prompt_dump_min.txt; line=2581; kind=http; pattern=Bearer ; text=headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}}.pattern))
  129:   - headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
  130: - **http** "core_prompt_dump_min.txt:2612" (pattern: $(@{file=core_prompt_dump_min.txt; line=2612; kind=http; pattern=Authorization; text=headers = {"Authorization": f"Bearer {api_key}"}}.pattern))
  131:   - headers = {"Authorization": f"Bearer {api_key}"}
  132: - **http** "core_prompt_dump_min.txt:2612" (pattern: $(@{file=core_prompt_dump_min.txt; line=2612; kind=http; pattern=Bearer ; text=headers = {"Authorization": f"Bearer {api_key}"}}.pattern))
  133:   - headers = {"Authorization": f"Bearer {api_key}"}
  134: - **http** "core_prompt_dump_min.txt:2662" (pattern: $(@{file=core_prompt_dump_min.txt; line=2662; kind=http; pattern=base_url; text=self.base_url = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")}.pattern))
  135:   - self.base_url = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")
  136: - **http** "core_prompt_dump_min.txt:2671" (pattern: $(@{file=core_prompt_dump_min.txt; line=2671; kind=http; pattern=Authorization; text="Authorization": f"Bearer {self.api_key}",}.pattern))
-----

### Gemini block 7
**ops\reports\connector_audit_20260216_163225.md**  (hit line: 178)
-----
  168: - **http** "core_prompt_dump.txt:1419" (pattern: $(@{file=core_prompt_dump.txt; line=1419; kind=http; pattern=Authorization; text="Authorization": f"Bearer {OPENAI_API_KEY}",}.pattern))
  169:   - "Authorization": f"Bearer {OPENAI_API_KEY}",
  170: - **http** "core_prompt_dump.txt:1419" (pattern: $(@{file=core_prompt_dump.txt; line=1419; kind=http; pattern=Bearer ; text="Authorization": f"Bearer {OPENAI_API_KEY}",}.pattern))
  171:   - "Authorization": f"Bearer {OPENAI_API_KEY}",
  172: - **http** "core_prompt_dump.txt:1560" (pattern: $(@{file=core_prompt_dump.txt; line=1560; kind=http; pattern=http_status; text=for attr in ("status_code", "http_status", "status"):}.pattern))
  173:   - for attr in ("status_code", "http_status", "status"):
  174: - **http** "core_prompt_dump.txt:1753" (pattern: $(@{file=core_prompt_dump.txt; line=1753; kind=http; pattern=404; text=if status in (400, 404, 409, 422):}.pattern))
  175:   - if status in (400, 404, 409, 422):
  176: - **claude** "core_prompt_dump.txt:2966" (pattern: $(@{file=core_prompt_dump.txt; line=2966; kind=claude; pattern=anthropic; text="ANTHROPIC_API_KEY": present("ANTHROPIC_API_KEY"),}.pattern))
  177:   - "ANTHROPIC_API_KEY": present("ANTHROPIC_API_KEY"),
  178: - **gemini** "core_prompt_dump.txt:3052" (pattern: $(@{file=core_prompt_dump.txt; line=3052; kind=gemini; pattern=gemini-; text=gemini_model = "gemini-2.5-flash"}.pattern))
  179:   - gemini_model = "gemini-2.5-flash"
  180: - **claude** "core_prompt_dump.txt:3053" (pattern: $(@{file=core_prompt_dump.txt; line=3053; kind=claude; pattern=claude-; text=claude_model = "claude-3-5-sonnet-20241022"}.pattern))
  181:   - claude_model = "claude-3-5-sonnet-20241022"
  182: - **gemini** "core_prompt_dump.txt:3090" (pattern: $(@{file=core_prompt_dump.txt; line=3090; kind=gemini; pattern=gemini-; text=gemini_model = "gemini-2.5-flash"}.pattern))
  183:   - gemini_model = "gemini-2.5-flash"
  184: - **claude** "core_prompt_dump.txt:3091" (pattern: $(@{file=core_prompt_dump.txt; line=3091; kind=claude; pattern=claude-; text=claude_model = "claude-3-5-sonnet-20241022"}.pattern))
  185:   - claude_model = "claude-3-5-sonnet-20241022"
  186: - **gemini** "core_prompt_dump.txt:3339" (pattern: $(@{file=core_prompt_dump.txt; line=3339; kind=gemini; pattern=generativelanguage.googleapis.com; text=Google Gemini API (generativelanguage.googleapis.com) 호출 최소 구현.}.pattern))
  187:   - Google Gemini API (generativelanguage.googleapis.com) 호출 최소 구현.
  188: - **gemini** "core_prompt_dump.txt:3339" (pattern: $(@{file=core_prompt_dump.txt; line=3339; kind=gemini; pattern=googleapis; text=Google Gemini API (generativelanguage.googleapis.com) 호출 최소 구현.}.pattern))
  189:   - Google Gemini API (generativelanguage.googleapis.com) 호출 최소 구현.
  190: - **gemini** "core_prompt_dump.txt:3343" (pattern: $(@{file=core_prompt_dump.txt; line=3343; kind=gemini; pattern=gemini-; text=- ORCHESTRA_GEMINI_MODEL (없으면 GEMINI_MODEL, 그마저 없으면 gemini-2.0-flash)}.pattern))
  191:   - - ORCHESTRA_GEMINI_MODEL (없으면 GEMINI_MODEL, 그마저 없으면 gemini-2.0-flash)
  192: - **gemini** "core_prompt_dump.txt:3357" (pattern: $(@{file=core_prompt_dump.txt; line=3357; kind=gemini; pattern=gemini-; text=self.model = (os.getenv("ORCHESTRA_GEMINI_MODEL") or os.getenv("GEMINI_MODEL") or "gemini-2.0-flash").strip()}.pattern))
  193:   - self.model = (os.getenv("ORCHESTRA_GEMINI_MODEL") or os.getenv("GEMINI_MODEL") or "gemini-2.0-flash").strip()
  194: - **gemini** "core_prompt_dump.txt:3386" (pattern: $(@{file=core_prompt_dump.txt; line=3386; kind=gemini; pattern=generativelanguage.googleapis.com; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"}.pattern))
  195:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"
  196: - **gemini** "core_prompt_dump.txt:3386" (pattern: $(@{file=core_prompt_dump.txt; line=3386; kind=gemini; pattern=generateContent; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"}.pattern))
-----

### Gemini block 8
**ops\reports\connector_audit_20260216_163225.md**  (hit line: 197)
-----
  187:   - Google Gemini API (generativelanguage.googleapis.com) 호출 최소 구현.
  188: - **gemini** "core_prompt_dump.txt:3339" (pattern: $(@{file=core_prompt_dump.txt; line=3339; kind=gemini; pattern=googleapis; text=Google Gemini API (generativelanguage.googleapis.com) 호출 최소 구현.}.pattern))
  189:   - Google Gemini API (generativelanguage.googleapis.com) 호출 최소 구현.
  190: - **gemini** "core_prompt_dump.txt:3343" (pattern: $(@{file=core_prompt_dump.txt; line=3343; kind=gemini; pattern=gemini-; text=- ORCHESTRA_GEMINI_MODEL (없으면 GEMINI_MODEL, 그마저 없으면 gemini-2.0-flash)}.pattern))
  191:   - - ORCHESTRA_GEMINI_MODEL (없으면 GEMINI_MODEL, 그마저 없으면 gemini-2.0-flash)
  192: - **gemini** "core_prompt_dump.txt:3357" (pattern: $(@{file=core_prompt_dump.txt; line=3357; kind=gemini; pattern=gemini-; text=self.model = (os.getenv("ORCHESTRA_GEMINI_MODEL") or os.getenv("GEMINI_MODEL") or "gemini-2.0-flash").strip()}.pattern))
  193:   - self.model = (os.getenv("ORCHESTRA_GEMINI_MODEL") or os.getenv("GEMINI_MODEL") or "gemini-2.0-flash").strip()
  194: - **gemini** "core_prompt_dump.txt:3386" (pattern: $(@{file=core_prompt_dump.txt; line=3386; kind=gemini; pattern=generativelanguage.googleapis.com; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"}.pattern))
  195:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"
  196: - **gemini** "core_prompt_dump.txt:3386" (pattern: $(@{file=core_prompt_dump.txt; line=3386; kind=gemini; pattern=generateContent; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"}.pattern))
  197:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"
  198: - **gemini** "core_prompt_dump.txt:3386" (pattern: $(@{file=core_prompt_dump.txt; line=3386; kind=gemini; pattern=models/; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"}.pattern))
  199:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"
  200: - **gemini** "core_prompt_dump.txt:3386" (pattern: $(@{file=core_prompt_dump.txt; line=3386; kind=gemini; pattern=googleapis; text=url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"}.pattern))
  201:   - url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"
  202: - **http** "core_prompt_dump.txt:3461" (pattern: $(@{file=core_prompt_dump.txt; line=3461; kind=http; pattern=Authorization; text=headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}}.pattern))
  203:   - headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
  204: - **http** "core_prompt_dump.txt:3461" (pattern: $(@{file=core_prompt_dump.txt; line=3461; kind=http; pattern=Bearer ; text=headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}}.pattern))
  205:   - headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
  206: - **http** "core_prompt_dump.txt:3492" (pattern: $(@{file=core_prompt_dump.txt; line=3492; kind=http; pattern=Authorization; text=headers = {"Authorization": f"Bearer {api_key}"}}.pattern))
  207:   - headers = {"Authorization": f"Bearer {api_key}"}
  208: - **http** "core_prompt_dump.txt:3492" (pattern: $(@{file=core_prompt_dump.txt; line=3492; kind=http; pattern=Bearer ; text=headers = {"Authorization": f"Bearer {api_key}"}}.pattern))
  209:   - headers = {"Authorization": f"Bearer {api_key}"}
  210: - **http** "core_prompt_dump.txt:3542" (pattern: $(@{file=core_prompt_dump.txt; line=3542; kind=http; pattern=base_url; text=self.base_url = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")}.pattern))
  211:   - self.base_url = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")
  212: - **http** "core_prompt_dump.txt:3551" (pattern: $(@{file=core_prompt_dump.txt; line=3551; kind=http; pattern=Authorization; text="Authorization": f"Bearer {self.api_key}",}.pattern))
  213:   - "Authorization": f"Bearer {self.api_key}",
  214: - **http** "core_prompt_dump.txt:3551" (pattern: $(@{file=core_prompt_dump.txt; line=3551; kind=http; pattern=Bearer ; text="Authorization": f"Bearer {self.api_key}",}.pattern))
  215:   - "Authorization": f"Bearer {self.api_key}",
-----

### Gemini block 9
**orchestra__backup_20260213_214212\orchestra__backup_20260213_214212\core_prompt_dump.txt**  (hit line: 3052)
-----
 3042: async def ask_upload_route(
 3043:     mode: str = Form("fact"),
 3044:     question: str = Form(""),
 3045:     files: List[UploadFile] = File(default=[]),
 3046: ):
 3047:     q = (question or "").strip()
 3048:     if not q:
 3049:         return {"ok": False, "error": "question is required"}
 3050: 
 3051:     m = (mode or "fact").strip().lower()
 3052:     gemini_model = "gemini-2.5-flash"
 3053:     claude_model = "claude-3-5-sonnet-20241022"
 3054:     pplx_model = "sonar"
 3055: 
 3056:     docs, imgs, errors = await extract_files(files or [])
 3057:     docs2 = await summarize_docs_if_needed(docs, claude_model=claude_model)
 3058:     image_summaries = await summarize_images_with_gemini(imgs, gemini_model=gemini_model) if imgs else []
 3059: 
 3060:     file_ctx = build_file_context(docs2, image_summaries=image_summaries)
 3061:     full_q = q + (("\n\n[업로드 파일 내용]\n" + file_ctx) if file_ctx else "")
 3062: 
 3063:     if m == "fact":
 3064:         r = await ask_gemini(_wrap_user_question("fact", full_q), model=gemini_model)
 3065:         r.pop("raw", None); r["provider"] = "gemini"
 3066:         return {"ok": True, "mode": m, "question": q, "files": {"docs": len(docs2), "images": len(imgs), "errors": errors}, "result": r}
 3067: 
 3068:     if m == "code":
 3069:         r = await ask_claude(_wrap_user_question("code", full_q), model=claude_model)
 3070:         r.pop("raw", None); r["provider"] = "claude"
-----

### Gemini block 10
**orchestra__backup_20260213_214212\orchestra__backup_20260213_214212\core_prompt_dump.txt**  (hit line: 3090)
-----
 3080: 
 3081: @app.post("/ask_upload/merge")
 3082: async def ask_upload_merge(
 3083:     question: str = Form(""),
 3084:     files: List[UploadFile] = File(default=[]),
 3085: ):
 3086:     q = (question or "").strip()
 3087:     if not q:
 3088:         return {"ok": False, "error": "question is required"}
 3089: 
 3090:     gemini_model = "gemini-2.5-flash"
 3091:     claude_model = "claude-3-5-sonnet-20241022"
 3092:     pplx_model = "sonar"
 3093: 
 3094:     docs, imgs, errors = await extract_files(files or [])
 3095:     docs2 = await summarize_docs_if_needed(docs, claude_model=claude_model)
 3096:     image_summaries = await summarize_images_with_gemini(imgs, gemini_model=gemini_model) if imgs else []
 3097: 
 3098:     file_ctx = build_file_context(docs2, image_summaries=image_summaries)
 3099:     full_q = q + (("\n\n[업로드 파일 내용]\n" + file_ctx) if file_ctx else "")
 3100: 
 3101:     g, c, p = await asyncio.gather(
 3102:         ask_gemini(_wrap_user_question("fact", full_q), model=gemini_model),
 3103:         ask_claude(_wrap_user_question("code", full_q), model=claude_model),
 3104:         ask_perplexity(_wrap_user_question("research", full_q), model=pplx_model),
 3105:     )
 3106: 
 3107:     gtxt = g.get("text", "") if isinstance(g, dict) else ""
 3108:     ctxt = c.get("text", "") if isinstance(c, dict) else ""
-----

### Gemini block 11
**orchestra__backup_20260213_214212\orchestra__backup_20260213_214212\core_prompt_dump.txt**  (hit line: 3339)
-----
 3329: from __future__ import annotations
 3330: 
 3331: import os
 3332: from typing import Any, Dict, Optional
 3333: 
 3334: import httpx
 3335: 
 3336: 
 3337: class GeminiProvider:
 3338:     """
 3339:     Google Gemini API (generativelanguage.googleapis.com) 호출 최소 구현.
 3340: 
 3341:     - env:
 3342:       - GEMINI_API_KEY (또는 GOOGLE_API_KEY)
 3343:       - ORCHESTRA_GEMINI_MODEL (없으면 GEMINI_MODEL, 그마저 없으면 gemini-2.0-flash)
 3344: 
 3345:     contract:
 3346:       - 성공 시 dict 반환:
 3347:         {
 3348:           "text": "...",
 3349:           "format": "plain",
 3350:           "meta": { "provider": "gemini", "model": "<model>" }
 3351:         }
 3352:       - 실패 시도 dict 반환(예외 대신)하여 ws_core.ensure_contract()가 안정적으로 감쌈
 3353:     """
 3354: 
 3355:     def __init__(self) -> None:
 3356:         self.api_key = (os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY") or "").strip()
 3357:         self.model = (os.getenv("ORCHESTRA_GEMINI_MODEL") or os.getenv("GEMINI_MODEL") or "gemini-2.0-flash").strip()
-----

### Gemini block 12
**orchestra__backup_20260213_214212\orchestra__backup_20260213_214212\core_prompt_dump.txt**  (hit line: 3386)
-----
 3376:         context = context or {}
 3377:         params = params or {}
 3378: 
 3379:         if task_type != "text":
 3380:             return {
 3381:                 "ok": False,
 3382:                 "error": "gemini_provider_task_type_not_supported_yet",
 3383:                 "meta": {"provider": "gemini", "model": self.model},
 3384:             }
 3385: 
 3386:         url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"
 3387: 
 3388:         body: Dict[str, Any] = {
 3389:             "contents": [{"parts": [{"text": message}]}],
 3390:         }
 3391: 
 3392:         if isinstance(params.get("generationConfig"), dict):
 3393:             body["generationConfig"] = params["generationConfig"]
 3394:         if isinstance(params.get("safetySettings"), list):
 3395:             body["safetySettings"] = params["safetySettings"]
 3396:         if isinstance(params.get("systemInstruction"), dict):
 3397:             body["systemInstruction"] = params["systemInstruction"]
 3398: 
 3399:         headers = {"Content-Type": "application/json; charset=utf-8"}
 3400: 
 3401:         try:
 3402:             with httpx.Client(timeout=self.timeout_s) as client:
 3403:                 r = client.post(url, params={"key": self.api_key}, json=body, headers=headers)
 3404:                 r.raise_for_status()
-----
