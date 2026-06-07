import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { buildSystemPrompt } from "./prompt";

const http = httpRouter();

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Resolve the bearer token on a request to a user, or null.
async function authUser(ctx: any, req: Request) {
  const header = req.headers.get("Authorization") || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) return null;
  return await ctx.runQuery(internal.model.userByToken, { token });
}

function newToken(): string {
  return crypto.randomUUID() + crypto.randomUUID().replace(/-/g, "");
}

function bytesToB64(b: Uint8Array): string {
  let s = "";
  for (const x of b) s += String.fromCharCode(x);
  return btoa(s);
}

function b64ToBytes(s: string): Uint8Array {
  const bin = atob(s);
  const u = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
  return u;
}

// PBKDF2-HMAC-SHA256, 100k iterations. Returns base64 hash + salt.
async function hashPassword(
  password: string,
  saltB64?: string,
): Promise<{ hash: string; salt: string }> {
  const salt = saltB64 ? b64ToBytes(saltB64) : crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt, iterations: 100000, hash: "SHA-256" },
    key,
    256,
  );
  return { hash: bytesToB64(new Uint8Array(bits)), salt: bytesToB64(salt) };
}

// POST /auth/signup  { email, password } -> { token } | 409 email_taken
http.route({
  path: "/auth/signup",
  method: "POST",
  handler: httpAction(async (ctx, req) => {
    const body = await req.json().catch(() => ({}));
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body.password === "string" ? body.password : "";
    if (!email || !email.includes("@")) return json({ error: "bad_email" }, 400);
    if (password.length < 8) return json({ error: "weak_password" }, 400);

    const { hash, salt } = await hashPassword(password);
    const token = newToken();
    const res = await ctx.runMutation(internal.model.createUser, {
      email,
      passwordHash: hash,
      passwordSalt: salt,
      token,
      now: Date.now(),
    });
    if (!res) return json({ error: "email_taken" }, 409);
    return json({ token });
  }),
});

// POST /auth/signin  { email, password } -> { token } | 401
http.route({
  path: "/auth/signin",
  method: "POST",
  handler: httpAction(async (ctx, req) => {
    const body = await req.json().catch(() => ({}));
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body.password === "string" ? body.password : "";
    if (!email || !password) return json({ error: "bad_request" }, 400);

    const auth = await ctx.runQuery(internal.model.getUserAuth, { email });
    if (!auth) return json({ error: "invalid_credentials" }, 401);
    const { hash } = await hashPassword(password, auth.passwordSalt);
    if (hash !== auth.passwordHash) return json({ error: "invalid_credentials" }, 401);

    const token = newToken();
    await ctx.runMutation(internal.model.createSession, {
      userId: auth.userId,
      token,
      now: Date.now(),
    });
    return json({ token });
  }),
});

// POST /v1/clean  { text, tone, accuracy, app, dictionary, codeMode } -> { cleaned }
http.route({
  path: "/v1/clean",
  method: "POST",
  handler: httpAction(async (ctx, req) => {
    const user = await authUser(ctx, req);
    if (!user) return json({ error: "unauthorized" }, 401);

    const day = new Date().toISOString().slice(0, 10);
    const { allowed } = await ctx.runMutation(internal.model.checkAndBumpUsage, {
      userId: user._id,
      day,
    });
    if (!allowed) return json({ error: "quota_exceeded", resetAt: `${day}T23:59:59Z` }, 429);

    const body = await req.json().catch(() => ({}));
    const text = (body.text || "").toString();
    if (!text.trim()) return json({ cleaned: "" });
    if (text.length > 8000) return json({ error: "too_long" }, 413);

    // Default to OpenRouter (OpenAI-compatible). Only UPSTREAM_API_KEY is required.
    const endpoint =
      process.env.UPSTREAM_ENDPOINT || "https://openrouter.ai/api/v1/chat/completions";
    const model = process.env.UPSTREAM_MODEL || "openai/gpt-4o-mini";

    const system = buildSystemPrompt(body);
    let upstream: Response;
    try {
      upstream = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${process.env.UPSTREAM_API_KEY}`,
          // OpenRouter attribution headers (ignored by other providers).
          "HTTP-Referer": "https://dict.tianxu.cloud",
          "X-Title": "Dict",
        },
        body: JSON.stringify({
          model,
          messages: [
            { role: "system", content: system },
            { role: "user", content: `[TRANSCRIPTION TO CLEAN]: ${text}` },
          ],
          temperature: 0.3,
          max_tokens: 2048,
        }),
      });
    } catch {
      return json({ error: "upstream_unreachable" }, 502);
    }
    if (!upstream.ok) return json({ error: "upstream_error", status: upstream.status }, 502);
    const data = await upstream.json();
    const cleaned = (data?.choices?.[0]?.message?.content || "").trim();
    return json({ cleaned: cleaned || text });
  }),
});

// GET /v1/flags -> { flags: { key: bool, ... } }
http.route({
  path: "/v1/flags",
  method: "GET",
  handler: httpAction(async (ctx, req) => {
    const user = await authUser(ctx, req);
    if (!user) return json({ error: "unauthorized" }, 401);
    const flags = await ctx.runQuery(internal.model.flagsForUser, { userId: user._id });
    return json({ flags });
  }),
});

export default http;
