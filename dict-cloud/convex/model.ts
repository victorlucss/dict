import { internalMutation, internalQuery } from "./_generated/server";
import { v } from "convex/values";

const CODE_TTL_MS = 10 * 60 * 1000; // login codes valid 10 minutes
const FREE_DAILY_LIMIT = 100; // cleanups/day per user on the free tier

// Store a fresh login code for an email, replacing any previous one.
export const storeCode = internalMutation({
  args: { email: v.string(), code: v.string(), now: v.number() },
  handler: async (ctx, { email, code, now }) => {
    const existing = await ctx.db
      .query("loginCodes")
      .withIndex("by_email", (q) => q.eq("email", email))
      .collect();
    for (const e of existing) await ctx.db.delete(e._id);
    await ctx.db.insert("loginCodes", { email, code, expiresAt: now + CODE_TTL_MS });
  },
});

// Validate a code; on success create/find the user and persist a session token.
export const verifyCode = internalMutation({
  args: { email: v.string(), code: v.string(), token: v.string(), now: v.number() },
  returns: v.union(v.null(), v.object({ userId: v.id("users") })),
  handler: async (ctx, { email, code, token, now }) => {
    const rec = await ctx.db
      .query("loginCodes")
      .withIndex("by_email", (q) => q.eq("email", email))
      .first();
    if (!rec || rec.code !== code || rec.expiresAt < now) return null;
    await ctx.db.delete(rec._id);

    let user = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", email))
      .first();
    if (!user) {
      const id = await ctx.db.insert("users", { email, createdAt: now });
      user = await ctx.db.get(id);
    }
    await ctx.db.insert("sessions", { userId: user!._id, token, createdAt: now });
    return { userId: user!._id };
  },
});

// Resolve a bearer token to a user (or null).
export const userByToken = internalQuery({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    const s = await ctx.db
      .query("sessions")
      .withIndex("by_token", (q) => q.eq("token", token))
      .first();
    if (!s) return null;
    const user = await ctx.db.get(s.userId);
    if (!user) return null;
    return { _id: user._id, email: user.email };
  },
});

// Effective feature flags for a user = catalog defaults overlaid with per-user overrides.
export const flagsForUser = internalQuery({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    const user = await ctx.db.get(userId);
    const overrides = user?.flags ?? {};
    const catalog = await ctx.db.query("featureFlags").collect();
    const result: Record<string, boolean> = {};
    for (const f of catalog) result[f.key] = overrides[f.key] ?? f.enabledByDefault;
    for (const [k, val] of Object.entries(overrides)) {
      if (!(k in result)) result[k] = val;
    }
    return result;
  },
});

// Per-user daily rate limit. Returns whether this request is allowed (and counts it).
export const checkAndBumpUsage = internalMutation({
  args: { userId: v.id("users"), day: v.string() },
  returns: v.object({ allowed: v.boolean() }),
  handler: async (ctx, { userId, day }) => {
    const bucket = `${userId}:${day}`;
    const rec = await ctx.db
      .query("usage")
      .withIndex("by_bucket", (q) => q.eq("bucket", bucket))
      .first();
    const count = rec?.count ?? 0;
    if (count >= FREE_DAILY_LIMIT) return { allowed: false };
    if (rec) await ctx.db.patch(rec._id, { count: count + 1 });
    else await ctx.db.insert("usage", { bucket, count: 1 });
    return { allowed: true };
  },
});
