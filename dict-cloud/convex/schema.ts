import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  // One row per account. Password is stored as a PBKDF2 hash + salt, never plain.
  users: defineTable({
    email: v.string(),
    passwordHash: v.string(),
    passwordSalt: v.string(),
    createdAt: v.number(),
    // Per-user feature-flag overrides (flag key -> on/off). Absent = use default.
    flags: v.optional(v.record(v.string(), v.boolean())),
  }).index("by_email", ["email"]),

  // Long-lived bearer tokens issued after sign-up / sign-in.
  sessions: defineTable({
    userId: v.id("users"),
    token: v.string(),
    createdAt: v.number(),
  }).index("by_token", ["token"]),

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
