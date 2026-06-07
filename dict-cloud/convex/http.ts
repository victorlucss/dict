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

// Email a 6-digit code (Resend); in dev (no key) just log it.
async function sendCodeEmail(email: string, code: string) {
  const key = process.env.RESEND_API_KEY;
  if (!key) {
    console.log(`[dict-cloud] dev login code for ${email}: ${code}`);
    return;
  }
  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      from: process.env.MAIL_FROM || "Dict <login@dict.tianxu.cloud>",
      to: email,
      subject: "Your Dict sign-in code",
      text: `Your Dict sign-in code is ${code}. It expires in 10 minutes.`,
    }),
  });
}

// POST /auth/request-code  { email } -> { ok: true }
http.route({
  path: "/auth/request-code",
  method: "POST",
  handler: httpAction(async (ctx, req) => {
    const body = await req.json().catch(() => ({}));
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    if (!email || !email.includes("@")) return json({ error: "bad_email" }, 400);
    const code = String(Math.floor(100000 + Math.random() * 900000));
    await ctx.runMutation(internal.model.storeCode, { email, code, now: Date.now() });
    await sendCodeEmail(email, code);
    return json({ ok: true });
  }),
});

// POST /auth/verify  { email, code } -> { token } | 401
http.route({
  path: "/auth/verify",
  method: "POST",
  handler: httpAction(async (ctx, req) => {
    const body = await req.json().catch(() => ({}));
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const code = typeof body.code === "string" ? body.code.trim() : "";
    if (!email || !code) return json({ error: "bad_request" }, 400);
    const token = crypto.randomUUID() + crypto.randomUUID().replace(/-/g, "");
    const res = await ctx.runMutation(internal.model.verifyCode, {
      email,
      code,
      token,
      now: Date.now(),
    });
    if (!res) return json({ error: "invalid_code" }, 401);
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

    const system = buildSystemPrompt(body);
    let upstream: Response;
    try {
      upstream = await fetch(process.env.UPSTREAM_ENDPOINT!, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${process.env.UPSTREAM_API_KEY}`,
        },
        body: JSON.stringify({
          model: process.env.UPSTREAM_MODEL,
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
