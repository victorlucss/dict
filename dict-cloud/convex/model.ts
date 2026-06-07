import { internalMutation, internalQuery } from "./_generated/server";
import { v } from "convex/values";

const DEFAULT_FREE_LIMIT = 100; // fallback if the "free" plan row is missing

// Resolve a user's plan key + daily limit (null = unlimited).
async function resolvePlan(ctx: any, userId: any): Promise<{ plan: string; limit: number | null }> {
  const user = await ctx.db.get(userId);
  const planKey = user?.plan ?? "free";
  const row = await ctx.db
    .query("plans")
    .withIndex("by_key", (q: any) => q.eq("key", planKey))
    .first();
  const limit = row ? row.dailyLimit : planKey === "unlimited" ? null : DEFAULT_FREE_LIMIT;
  return { plan: planKey, limit };
}

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

// Per-user daily limit driven by the user's plan. Counts the request if allowed.
// Unlimited plans (limit === null) are always allowed (and still counted).
export const checkAndBumpUsage = internalMutation({
  args: { userId: v.id("users"), day: v.string() },
  returns: v.object({
    allowed: v.boolean(),
    used: v.number(),
    limit: v.union(v.number(), v.null()),
    plan: v.string(),
  }),
  handler: async (ctx, { userId, day }) => {
    const { plan, limit } = await resolvePlan(ctx, userId);
    const bucket = `${userId}:${day}`;
    const rec = await ctx.db
      .query("usage")
      .withIndex("by_bucket", (q) => q.eq("bucket", bucket))
      .first();
    const used = rec?.count ?? 0;
    if (limit !== null && used >= limit) {
      return { allowed: false, used, limit, plan };
    }
    if (rec) await ctx.db.patch(rec._id, { count: used + 1 });
    else await ctx.db.insert("usage", { bucket, count: 1 });
    return { allowed: true, used: used + 1, limit, plan };
  },
});

// Read-only account status: plan, daily limit, usage today, and feature flags.
export const accountStatus = internalQuery({
  args: { userId: v.id("users"), day: v.string() },
  handler: async (ctx, { userId, day }) => {
    const { plan, limit } = await resolvePlan(ctx, userId);
    const bucket = `${userId}:${day}`;
    const rec = await ctx.db
      .query("usage")
      .withIndex("by_bucket", (q) => q.eq("bucket", bucket))
      .first();
    const user = await ctx.db.get(userId);
    const overrides = user?.flags ?? {};
    const catalog = await ctx.db.query("featureFlags").collect();
    const flags: Record<string, boolean> = {};
    for (const f of catalog) flags[f.key] = overrides[f.key] ?? f.enabledByDefault;
    for (const [k, val] of Object.entries(overrides)) if (!(k in flags)) flags[k] = val;
    return { plan, dailyLimit: limit, usedToday: rec?.count ?? 0, flags };
  },
});
