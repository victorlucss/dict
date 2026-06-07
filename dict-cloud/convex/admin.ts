import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

// Define or update a global feature flag (run from the Convex dashboard).
// e.g. defineFlag({ key: "realtime_streaming", description: "Live transcription", enabledByDefault: false })
export const defineFlag = mutation({
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
export const setUserFlag = mutation({
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
export const listFlags = query({
  args: {},
  handler: async (ctx) => ctx.db.query("featureFlags").collect(),
});
