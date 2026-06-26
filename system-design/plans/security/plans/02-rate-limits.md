# 🚦 Rate Limits

## Background

⛔ BLOCKED[Gate] — requires parent plan/01-service-boundaries.md VERIFY task (service
module names finalised — rate limit scopes reference service names).
⛔ BLOCKED[Gate] — requires plan/01-jwt-sessions.md DECIDE task (JWT model decided —
user-scoped rate limits require a confirmed user identifier in the token).

Rate limits are the last line of defence against credential stuffing, OTP brute-force,
and objection submission spam. They must be defined before the API contracts are written
because every service contract includes a rate-limit note.

## Description

Define rate limits for every REST endpoint category. Choose the Node.js rate-limiting
middleware (`express-rate-limit` or equivalent). Specify scope (IP / user / phone),
window, and limit for each category. Define the response shape when a limit is exceeded.

## Purpose

To answer: "what is the worst-case rate abuse pattern for each endpoint category — and
what limit stops it without blocking a legitimate user who has a slow connection or a
trigger-happy retry loop?"

## Goal

`easy_rates/system-design/docs/security/rate-limits.md` — four endpoint categories
with named middleware, scope, window, and limit; response shape for 429; Redis store
decision for distributed environments.

## Tasks

- [x] ✅ THINK `/socratic "What is the most damaging rate-abuse scenario for each
  endpoint category — credential stuffing on /auth/login, OTP brute-force on
  /otp/verify, property-lookup scraping on /property, or mass objection filing on
  /objection — and what limit stops the attack without impacting a legitimate user
  who is just slow or retrying due to a network error?"`
  Done when: each category has a named worst-case abuse scenario; the limit is
  motivated by that scenario, not by a round number.

- [x] ✅ LEARN `/unpack "express-rate-limit — keyGenerator for IP vs userId vs
  phoneNumber, windowMs and max parameters, standardHeaders and legacyHeaders,
  memory store vs Redis store (rate-limit-redis) for distributed Node.js environments,
  and the 429 response shape with Retry-After header"`
  Done when: you can write an express-rate-limit configuration for a user-scoped
  endpoint from memory; you know when to use the Redis store and when the memory
  store suffices.

- [x] ✅ DEFINE Define rate limits for four endpoint categories:
  AUTH (login, register, forgot-password):
    Scope: IP address
    Window and limit: motivated by credential-stuffing attack scenario
    Middleware: express-rate-limit with IP keyGenerator
  OTP (send, verify, resend):
    Scope: phone number (extracted from request body or JWT claim)
    Window and limit: motivated by OTP brute-force scenario
    Middleware: express-rate-limit with custom keyGenerator for phone number
    Note: OTP attempt counting is also enforced at the Twilio layer (max_attempts
    from twilio-integration.md) — this is a complementary server-side layer
  READ (property lookup, bill fetch, notification list):
    Scope: authenticated userId
    Window and limit: motivated by data-scraping scenario
    Middleware: express-rate-limit with userId from JWT claim
  WRITE (objection create, draft save):
    Scope: authenticated userId
    Window and limit: motivated by mass-filing scenario
    Middleware: express-rate-limit with userId from JWT claim
  For each: write the limit as `N requests per W minutes per [scope]` and justify N.
  Done when: all four categories defined; every limit has a one-line justification.

- [x] ✅ RESPONSE Define the 429 response shape:
  HTTP 429 Too Many Requests
  `{ "data": null, "error": { "code": "rate_limit_exceeded", "message": "...",
  "details": { "retryAfterSeconds": N } } }`
  `Retry-After` header: seconds until the window resets.
  Done when: 429 response shape is defined; Retry-After header is included;
  shape conforms to api/conventions.md error envelope.

- [x] ✅ STORE Decide: memory store (default, per-process, no Redis dependency)
  vs Redis store (rate-limit-redis, works across multiple Node.js instances).
  For pilot (single Node.js instance): memory store may suffice.
  For production (multiple instances behind a load balancer): Redis store required
  to prevent a user from bypassing limits by hitting different instances.
  State the decision and the scaling trigger that would require switching.
  Done when: decision documented; scaling trigger stated.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/security/rate-limits.md`:
  One table with columns: Category | Scope | Window | Limit | Middleware config |
  Abuse scenario.
  Include the 429 response shape and the store decision.
  Done when: all four categories in the table; 429 shape defined; store decision
  documented.

- [ ] ⚠️ VERIFY Twilio compatibility confirmed ✓ verified (OTP tier: 5 req/15 min/phone
  ≥ Twilio max_attempts; see rate-limits.md + twilio-integration.md).
  api/conventions.md cross-reference pending — api-contracts sub-scope not yet started.
  Done when: api/conventions.md written; 429 shape confirmed to match error envelope.

## Recommended skill

▶ `/socratic` ✅ — THINK task; naming the worst-case abuse scenario for each category
   before setting limits forces the limits to be grounded in actual attack patterns.
   alt: `/unpack` ✅ — express-rate-limit configuration and Redis store if the
   distributed rate-limiting pattern is unfamiliar.

## Engagement Instructions

Pass condition: all four endpoint categories have a defined limit with a one-line
justification referencing a named abuse scenario.
Pass condition: scope (IP / userId / phoneNumber) stated for each category.
Pass condition: 429 response shape defined and conforms to the error envelope pattern.
Pass condition: store decision (memory vs Redis) documented with a stated scaling trigger.
Pass condition: OTP rate limits are not tighter than the Twilio max_attempts parameter
from twilio-integration.md.
