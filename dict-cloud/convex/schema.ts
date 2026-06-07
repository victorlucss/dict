import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  // One row per signed-in person.
  users: defineTable({
    email: v.string(),
    createdAt: v.number(),
    // Per-user feature-flag overrides (flag key -> on/off). Absent = use default.
    flags: v.optional(v.record(v.string(), v.boolean())),
  }).index("by_email", ["email"]),

  // Long-lived bearer tokens issued after a successful OTP verification.
  sessions: defineTable({
    userId: v.id("users"),
    token: v.string(),
    createdAt: v.number(),
  }).index("by_token", ["token"]),

  // Short-lived one-time login codes emailed to a user.
  loginCodes: defineTable({
    email: v.string(),
    code: v.string(),
    expiresAt: v.number(),
  }).index("by_email", ["email"]),

  // Global feature-flag catalog + default state. Per-user overrides live on users.flags.
  featureFlags: defineTable({
    key: v.string(),
    description: v.string(),
    enabledByDefault: v.boolean(),
  }).index("by_key", ["key"]),

  // Per-user daily usage for rate limiting (key: `${userId}:${YYYY-MM-DD}`).
  usage: defineTable({
    bucket: v.string(),
    count: v.number(),
  }).index("by_bucket", ["bucket"]),
});
