import { internalMutation, internalQuery } from "./_generated/server";
import { v } from "convex/values";

// SECURITY: everything in this file must stay internal* — public mutation/query
// constructors would expose these operator-only functions to ANYONE who derives
// the deployment URL (it ships in the client binary), letting them self-grant
// flags/plans and tamper with accounts. Internal functions are still runnable
// from the Convex dashboard and `npx convex run`.

// Define or update a global feature flag (run from the Convex dashboard).
// e.g. defineFlag({ key: "realtime_streaming", description: "Live transcription", enabledByDefault: false })
export const defineFlag = internalMutation({
  args: {
    key: v.string(),
    description: v.string(),
    enabledByDefault: v.boolean(),
  },
  handler: async (ctx, { key, description, enabledByDefault }) => {
    const existing = await ctx.db
      .query("featureFlags")
      .withIndex("by_key", (q) => q.eq("key", key))
      .first();
    if (existing) {
      await ctx.db.patch(existing._id, { description, enabledByDefault });
    } else {
      await ctx.db.insert("featureFlags", { key, description, enabledByDefault });
    }
  },
});

// Turn a flag on/off for one user (by email) — how you enable an experiment for testers.
export const setUserFlag = internalMutation({
  args: { email: v.string(), key: v.string(), enabled: v.boolean() },
  handler: async (ctx, { email, key, enabled }) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", email.trim().toLowerCase()))
      .first();
    if (!user) throw new Error(`No user with email ${email}`);
    const flags = { ...(user.flags ?? {}), [key]: enabled };
    await ctx.db.patch(user._id, { flags });
  },
});

// Convenience: list the flag catalog.
export const listFlags = internalQuery({
  args: {},
  handler: async (ctx) => ctx.db.query("featureFlags").collect(),
});

// ----- Plans -------------------------------------------------------------

// Define or update a plan. dailyLimit null = unlimited.
// e.g. definePlan({ key: "free", name: "Free", dailyLimit: 100 })
//      definePlan({ key: "unlimited", name: "Unlimited", dailyLimit: null })
export const definePlan = internalMutation({
  args: { key: v.string(), name: v.string(), dailyLimit: v.union(v.number(), v.null()) },
  handler: async (ctx, { key, name, dailyLimit }) => {
    const existing = await ctx.db
      .query("plans")
      .withIndex("by_key", (q) => q.eq("key", key))
      .first();
    if (existing) await ctx.db.patch(existing._id, { name, dailyLimit });
    else await ctx.db.insert("plans", { key, name, dailyLimit });
  },
});

// Assign a plan to a user (by email). e.g. setUserPlan(email, "unlimited")
export const setUserPlan = internalMutation({
  args: { email: v.string(), plan: v.string() },
  handler: async (ctx, { email, plan }) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", email.trim().toLowerCase()))
      .first();
    if (!user) throw new Error(`No user with email ${email}`);
    await ctx.db.patch(user._id, { plan });
  },
});

export const listPlans = internalQuery({
  args: {},
  handler: async (ctx) => ctx.db.query("plans").collect(),
});

// Operator audit: every account's grants at a glance (safe fields only — never
// return passwordHash). e.g. `npx convex run admin:listUsers --prod`
export const listUsers = internalQuery({
  args: {},
  handler: async (ctx) => {
    const users = await ctx.db.query("users").collect();
    return users.map((u) => ({
      email: u.email,
      plan: u.plan ?? null,
      flags: u.flags ?? {},
      createdAt: new Date(u._creationTime).toISOString(),
    }));
  },
});
