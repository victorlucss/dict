# Dict Cloud (Convex backend)

Managed cleanup for Dict, with **accounts** and **feature flags**, on
[Convex](https://convex.dev). Users sign in with **email + password**; the
backend holds the upstream LLM key and cleans transcriptions server-side. Audio
never reaches this service — only the transcribed text. Full design in
[`../DICT-CLOUD.md`](../DICT-CLOUD.md).

## What's here

```
convex/
  schema.ts   users (email + PBKDF2 password hash), sessions, featureFlags, usage
  http.ts     POST /auth/signup, POST /auth/signin, POST /v1/clean, GET /v1/flags
  model.ts    internal DB queries/mutations used by the HTTP actions
  prompt.ts   buildSystemPrompt (mirrors the client's llm.rs)
  admin.ts    defineFlag / setUserFlag / listFlags (run from the dashboard)
```

## HTTP API

```jsonc
POST /auth/signup   { email, password }   -> { token } | 409 email_taken | 400  // password >= 8 chars
POST /auth/signin   { email, password }   -> { token } | 401                     // long-lived bearer token
POST /v1/clean      { text, tone, accuracy, app, dictionary, codeMode }
                    Authorization: Bearer <token>
                                          -> { cleaned } | 401 | 429
GET  /v1/flags      Authorization: Bearer <token>
                                          -> { flags: { key: bool } }
```

Passwords are stored as a PBKDF2-HMAC-SHA256 hash (100k iterations) + per-user salt.

The Dict client (`src-tauri/src/llm.rs`) calls `/v1/clean` with the stored token
when the LLM provider is **Dict Cloud**, and `/v1/flags` on launch to gate
experimental features.

## Setup

```bash
cd dict-cloud
npm install
npx convex dev            # logs in, creates a deployment, generates convex/_generated, watches

# Backend env (set in the Convex dashboard → Settings → Environment Variables,
# or: npx convex env set NAME value):
#   UPSTREAM_API_KEY    your OpenRouter key  (secret — REQUIRED)
#   UPSTREAM_ENDPOINT   optional; defaults to https://openrouter.ai/api/v1/chat/completions
#   UPSTREAM_MODEL      optional; defaults to openai/gpt-4o-mini
# Any OpenAI-compatible provider works — just override UPSTREAM_ENDPOINT/MODEL.
```

`npx convex dev` prints your deployment's **HTTP Actions URL**
(`https://<name>.convex.site`). Point the client at it: set
`DICT_CLOUD_ENDPOINT` in `src-tauri/src/llm.rs` to `https://<name>.convex.site`
(or map `api.dict.tianxu.cloud` to it), so `/v1/clean` resolves.

## Feature flags

```bash
# from the dashboard's Functions tab, or `npx convex run`:
npx convex run admin:defineFlag '{"key":"realtime_streaming","description":"Live transcription","enabledByDefault":false}'
npx convex run admin:setUserFlag '{"email":"you@example.com","key":"realtime_streaming","enabled":true}'
```

The client fetches `/v1/flags` and enables matching experimental features.

## Notes

- **Privacy:** transcripts aren't logged or stored — processed in memory, dropped.
- **Auth:** email + password → a bearer token stored on the client. Free tier is
  rate-limited per user/day (see `FREE_DAILY_LIMIT` in `model.ts`).
