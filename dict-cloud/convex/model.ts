import { internalMutation, internalQuery } from "./_generated/server";
import { v } from "convex/values";

const FREE_DAILY_LIMIT = 100; // cleanups/day per user on the free tier

// Create a new account (hash computed in the action). Fails if email is taken.
export const createUser = internalMutation({
  args: {
    email: v.string(),
    passwordHash: v.string(),
    passwordSalt: v.string(),
    token: v.string(),
    now: v.number(),
  },
  returns: v.union(v.null(), v.object({ userId: v.id("users") })),
  handler: async (ctx, { email, passwordHash, passwordSalt, token, now }) => {
    const existing = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", email))
      .first();
    if (existing) return null; // email already registered
    const userId = await ctx.db.insert("users", {
      email,
      passwordHash,
      passwordSalt,
      createdAt: now,
    });
    await ctx.db.insert("sessions", { userId, token, createdAt: now });
    return { userId };
  },
});

// Look up the stored hash + salt for sign-in (verification happens in the action).
export const getUserAuth = internalQuery({
  args: { email: v.string() },
  returns: v.union(
    v.null(),
    v.object({
      userId: v.id("users"),
      passwordHash: v.string(),
      passwordSalt: v.string(),
    }),
  ),
  handler: async (ctx, { email }) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", email))
      .first();
    if (!user) return null;
    return {
      userId: user._id,
      passwordHash: user.passwordHash,
      passwordSalt: user.passwordSalt,
    };
  },
});

// Persist a new session token after a successful sign-in.
export const createSession = internalMutation({
  args: { userId: v.id("users"), token: v.string(), now: v.number() },
  handler: async (ctx, { userId, token, now }) => {
    await ctx.db.insert("sessions", { userId, token, createdAt: now });
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
