# EasyRates — Rate Limits

**Status:** Decided  
**Date:** 2026-06-20  
**Downstream:** Copy the [Endpoint category table](#endpoint-category-table) into every
`api/*.md` contract as a non-functional constraint on each endpoint spec. Any endpoint
in `api/*.md` with no rate-limit category entry is a gap that must be resolved before
API contracts are locked.

---

## Library choice: express-rate-limit

**Chosen: `express-rate-limit` v7 with `rate-limit-redis` for production scaling.**

`express-rate-limit` is the de-facto standard for Express.js rate limiting. It supports
custom `keyGenerator` functions (enabling IP-, userId-, and phone-scoped limits on the
same middleware), emits RFC 9110-compliant `RateLimit-*` headers, and ships with a memory
store that requires zero infrastructure for a single-process deployment.

**Why not alternatives:**

| Library | Reason rejected |
|---|---|
| `express-slow-down` | Throttles (adds delay) instead of blocking. Does not stop credential stuffing — an attacker is willing to wait. |
| `bottleneck` | Server-side queue for outbound calls. Not designed for inbound HTTP rate limiting. |
| Custom Redis counter | ~50 lines that `express-rate-limit` already provides, plus no standard header support. Not justified. |
| `nestjs-throttler` | Requires NestJS framework. This project uses plain Express. |

**Configuration shared across all limiters:**

```typescript
import rateLimit, { Options } from 'express-rate-limit'

const SHARED: Partial<Options> = {
  standardHeaders: 'draft-8', // RateLimit-Limit, RateLimit-Remaining, RateLimit-Reset
  legacyHeaders: false,       // disable deprecated X-RateLimit-* headers
  handler: rateLimitHandler,  // see 429 Response Shape section
}
```

---

## Store decision: memory store (pilot) → Redis store (production)

**Pilot (Phase 1 — single Node.js process):** Use the default memory store. No Redis
dependency added. Per-process counters are accurate because all requests hit one process.

**Production trigger:** Any deployment with more than one Node.js instance — horizontal
scaling, a canary deploy with two instances, or a rolling restart with overlap. When two
instances run simultaneously, a user can bypass the limit by alternating between instances;
the memory store counter in each process counts only its share of traffic.

**When triggered:** Switch to `rate-limit-redis` backed by the existing Redis instance
(already in the architecture for OTP state: `otp_sid`, `otp_attempts`). No new
infrastructure is required — the same Redis connection string is reused.

```typescript
// Production upgrade — add to each limiter when scaling:
import { RedisStore } from 'rate-limit-redis'
import redisClient from '../shared/redis' // existing OTP Redis client

const store = new RedisStore({ client: redisClient, prefix: 'rl:' })
// Add `store` to SHARED config above
```

---

## Rate-limit categories

Six categories cover all 37 endpoints. Each is implemented as a distinct
`express-rate-limit` instance applied at the router level.

---

### 1. AUTH — credential stuffing / account enumeration

**Worst-case abuse:** Credential stuffing — an attacker iterates a leaked credential list
against `POST /auth/login`. At 1 request/second from one IP, they test 900 credentials in
15 minutes. Even a slow, stealthy tool running at 1 request/10 seconds tests 90 in the
same window.

**Scope:** IP address. User is unauthenticated; no userId exists at request time.

| Parameter | Value |
|---|---|
| Window | 15 minutes |
| Limit | 10 requests |
| Scope | IP (`req.ip`) |

**Justification:** A legitimate user re-requesting an OTP (mistyped phone, SMS not received)
will use ≤5 attempts. A 10-attempt ceiling over 15 minutes tolerates a couple of retry cycles
while forcing an OTP-spam / phone-enumeration tool to wait 15 minutes between every 10
requests — reducing throughput by ~5,400×.

```typescript
export const authLimiter = rateLimit({
  ...SHARED,
  windowMs: 15 * 60 * 1000,
  max: 10,
  keyGenerator: (req) => req.ip ?? 'unknown',
})
```

**Applied to:**
- `POST /auth/login`
- `POST /auth/register`
- `POST /auth/register/start`

---

### 2. OTP-VERIFY — per-code brute-force

**Worst-case abuse:** An attacker who has obtained a phone number but not the OTP
systematically tries all 6-digit codes (1,000,000 possibilities). Without a limit, a
script could attempt codes at network speed. Twilio enforces a fixed 5-attempt ceiling
per verification session (`OTP_MAX_INVALID_ATTEMPTS = 5`). The application-layer limit
is a complementary defence: it prevents an attacker from starting a new Twilio session
after each failure to reset the 5-attempt counter.

**Scope:** Phone number (`req.body.phone`). The phone number is the target of the attack;
different IPs can attack the same phone.

| Parameter | Value |
|---|---|
| Window | 10 minutes |
| Limit | 10 requests |
| Scope | phone number (`req.body.phone`) |

**Justification:** One OTP session allows 5 attempts. A user with a legitimately expired
code can request one resend and try again — 10 attempts per 10 minutes covers two full
sessions without triggering the limit. The limit stops an attacker who resets Twilio
sessions after each 5-attempt ceiling: they can only reset once per 10-minute window before
being blocked at the application layer.

**Twilio compatibility:** The application-layer limit (10/10 min) is looser than Twilio's
own 5-attempt ceiling per session. Twilio's limit fires first for a brute-force attempt;
this limit fires if the attacker circumvents it by starting new sessions. Compatible. ✓

```typescript
export const otpVerifyLimiter = rateLimit({
  ...SHARED,
  windowMs: 10 * 60 * 1000,
  max: 10,
  keyGenerator: (req) => req.body?.phone ?? req.ip ?? 'unknown',
})
```

**Applied to:**
- `POST /otp/verify`

---

### 3. OTP-SEND — SMS flooding / cost attack

**Worst-case abuse:** An attacker (or a buggy Dio client retry loop) sends repeated OTP
send/resend requests for a victim's phone number, racking up SMS costs at ~$0.16/SMS.
At 100 requests per hour, that is ~$16/hour against one phone number.

**Scope:** Phone number (`req.body.phone`). The phone number is the target and the cost
driver.

| Parameter | Value |
|---|---|
| Window | 10 minutes |
| Limit | 3 requests |
| Scope | phone number (`req.body.phone`) |

**Justification:** `OTP_MAX_RESENDS_PER_SESSION = 3`. The application-layer limit mirrors
the business rule exactly: 3 resends are permitted per session, and each session is bounded
by the 10-minute OTP TTL. After 3 resends, the user is directed to the support CTA. This
is not looser than Twilio's own resend counting; it enforces the same ceiling at the
middleware layer as a second line of defence if the Redis resend counter is bypassed.

**Twilio compatibility:** Application limit (3/10 min) matches `OTP_MAX_RESENDS_PER_SESSION`
exactly. Redis tracking fires first; this is the fallback if Redis is unavailable. ✓

```typescript
export const otpSendLimiter = rateLimit({
  ...SHARED,
  windowMs: 10 * 60 * 1000,
  max: 3,
  keyGenerator: (req) => req.body?.phone ?? req.ip ?? 'unknown',
})
```

**Applied to:**
- `POST /otp/resend`
- `POST /otp/send` (if exposed externally; currently only called internally)

---

### 4. READ — data scraping / financial data enumeration

**Worst-case abuse:** An attacker with a valid JWT systematically requests all bills and
account data for a ratepayer, or — if a bug exposes account numbers — iterates through
accounts to build a financial profile database. A scraper at 60 requests/minute captures
3,600 API responses per hour per JWT.

**Scope:** Authenticated userId (from JWT `sub` claim set by JWT middleware on `req.user`).
IP-based limiting would not help: a legitimate user on a carrier-grade NAT shares an IP
with thousands of other users.

| Parameter | Value |
|---|---|
| Window | 1 minute |
| Limit | 60 requests |
| Scope | userId (`req.user.id`) |

**Justification:** A user navigating the app makes at most 3-5 API calls per screen load.
A heavy session visiting 10 screens in a minute generates ~30-50 calls. The 60/minute
ceiling gives a 20% margin over heavy legitimate use while blocking automated scripts that
saturate the connection.

**Sub-limit — AI estimate:** `GET /bills/:id/ai-estimate` triggers an asynchronous
Databricks computation. Apply `aiEstimateLimiter` (below) *in addition to* `readLimiter`
on this route only.

```typescript
export const readLimiter = rateLimit({
  ...SHARED,
  windowMs: 60 * 1000,
  max: 60,
  keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown',
})

// Applied additionally to GET /bills/:id/ai-estimate only
export const aiEstimateLimiter = rateLimit({
  ...SHARED,
  windowMs: 60 * 1000,
  max: 5,
  keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown',
})
```

**Applied to:**
- `GET /auth/session`
- `GET /property/:id`
- `GET /property/:id/pdf`
- `GET /account/profile`
- `GET /account/properties`
- `GET /account/preferences`
- `GET /account/objections`
- `GET /bills/summary`
- `GET /bills`
- `GET /bills/:id`
- `GET /bills/:id/lines`
- `GET /bills/:id/ai-estimate` ← also gets `aiEstimateLimiter`
- `GET /objections/:id/summary`
- `GET /objections/:id/sufficiency`
- `GET /objections/:ref/status`
- `GET /notifications`

---

### 4b. SEARCH — account number and address enumeration

**Worst-case abuse:** An attacker iterates through account numbers or ERF numbers to
discover all ratepayers in the municipality — a POPIA breach by enumeration.
`POST /property/search/account` and `POST /property/search/address` are the two discovery
endpoints.

**Scope:** Authenticated userId. Property search requires login.

| Parameter | Value |
|---|---|
| Window | 1 minute |
| Limit | 10 requests |
| Scope | userId (`req.user.id`) |

**Justification:** A user searching for their property does 2-3 lookups at most (one
account number attempt, one address search, one confirmation). 10 per minute is 3×
the legitimate ceiling. A scraper iterating account numbers hits the limit after 10
requests and must wait 1 minute between bursts — reducing throughput by ~99%.

```typescript
export const searchLimiter = rateLimit({
  ...SHARED,
  windowMs: 60 * 1000,
  max: 10,
  keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown',
})
```

**Applied to:**
- `POST /property/search/account`
- `POST /property/search/address`

---

### 5. WRITE — mass filing / mutation spam

**Worst-case abuse:** A malfunctioning client or malicious script submits hundreds of
objection drafts, evidence uploads, or KYC documents — flooding Emfuleni's case management
system and the Azure Blob Storage bucket with junk records.

**Scope:** Authenticated userId.

| Parameter | Value |
|---|---|
| Window | 1 hour |
| Limit | 20 requests |
| Scope | userId (`req.user.id`) |

**Justification:** A user completing the full objection flow generates 3 write calls
(draft → evidence → submit). With 5 objections in one session, that is 15 write calls.
20 per hour gives a 33% margin over a heavy legitimate session while stopping automated
mass-filing (which would need dozens to hundreds of writes per hour).

```typescript
export const writeLimiter = rateLimit({
  ...SHARED,
  windowMs: 60 * 60 * 1000,
  max: 20,
  keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown',
})
```

**Applied to:**
- `POST /property/link`
- `PUT /account/preferences`
- `DELETE /account/properties/:id`
- `POST /bills/:id/review`
- `POST /auth/kyc`
- `POST /objections/draft`
- `POST /objections/:id/evidence`
- `POST /objections/:ref/probe`
- `POST /objections/:ref/escalate`
- `POST /objections/:ref/close`
- `POST /notifications/:id/read`
- `POST /notifications/device-token`

---

### 6. SUBMIT — objection submission (formal legal filing)

**Worst-case abuse:** An attacker scripts `POST /objections/:id/submit` to file dozens of
formal objections on behalf of one user, creating invalid records in Emfuleni's case
management system. Each submission triggers a queue task, an email, an SMS, and a
municipality adapter call.

**Scope:** Authenticated userId.

| Parameter | Value |
|---|---|
| Window | 24 hours |
| Limit | 5 requests |
| Scope | userId (`req.user.id`) |

**Justification:** A ratepayer with multiple properties might file 2-3 objections in one
billing cycle. 5 per day covers this with a margin. Filing more than 5 formal billing
objections in one day is implausible for a legitimate user in this context. The 24-hour
window (not 1 hour) reflects that the unit of work here is a formal legal submission, not
a UI interaction.

```typescript
export const submitLimiter = rateLimit({
  ...SHARED,
  windowMs: 24 * 60 * 60 * 1000,
  max: 5,
  keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown',
})
```

**Applied to:**
- `POST /objections/:id/submit`

---

### System endpoints (generous limits — not part of core categories)

| Endpoint | Scope | Window | Limit | Rationale |
|---|---|---|---|---|
| `POST /auth/refresh` | IP | 15 min | 30 | Dio interceptor calls once on 401; 30/15min prevents a looping client from flooding the endpoint |
| `POST /auth/logout` | userId | 15 min | 10 | Logout is called once per session; 10/15min tolerates a buggy retry without affecting legitimate users |

---

## Endpoint category table

Copy into each `api/*.md` contract. Every endpoint must have an entry.

| Endpoint | Method | Category | Scope | Window | Limit |
|---|---|---|---|---|---|
| `/auth/login` | POST | AUTH | IP | 15 min | 10 |
| `/auth/register` | POST | AUTH | IP | 15 min | 10 |
| `/auth/register/start` | POST | AUTH | IP | 15 min | 10 |
| `/auth/refresh` | POST | SYSTEM | IP | 15 min | 30 |
| `/auth/logout` | POST | SYSTEM | userId | 15 min | 10 |
| `/auth/kyc` | POST | WRITE | userId | 1 hour | 20 |
| `/auth/session` | GET | READ | userId | 1 min | 60 |
| `/otp/verify` | POST | OTP-VERIFY | phone | 10 min | 10 |
| `/otp/resend` | POST | OTP-SEND | phone | 10 min | 3 |
| `/otp/send` | POST | OTP-SEND | phone | 10 min | 3 |
| `/property/search/account` | POST | SEARCH | userId | 1 min | 10 |
| `/property/search/address` | POST | SEARCH | userId | 1 min | 10 |
| `/property/:id` | GET | READ | userId | 1 min | 60 |
| `/property/:id/pdf` | GET | READ | userId | 1 min | 60 |
| `/property/link` | POST | WRITE | userId | 1 hour | 20 |
| `/account/profile` | GET | READ | userId | 1 min | 60 |
| `/account/properties` | GET | READ | userId | 1 min | 60 |
| `/account/properties/:id` | DELETE | WRITE | userId | 1 hour | 20 |
| `/account/preferences` | GET | READ | userId | 1 min | 60 |
| `/account/preferences` | PUT | WRITE | userId | 1 hour | 20 |
| `/account/objections` | GET | READ | userId | 1 min | 60 |
| `/bills/summary` | GET | READ | userId | 1 min | 60 |
| `/bills` | GET | READ | userId | 1 min | 60 |
| `/bills/:id` | GET | READ | userId | 1 min | 60 |
| `/bills/:id/lines` | GET | READ | userId | 1 min | 60 |
| `/bills/:id/review` | POST | WRITE | userId | 1 hour | 20 |
| `/bills/:id/ai-estimate` | GET | READ + AI | userId | 1 min | 5 |
| `/objections/draft` | POST | WRITE | userId | 1 hour | 20 |
| `/objections/:id/evidence` | POST | WRITE | userId | 1 hour | 20 |
| `/objections/:id/summary` | GET | READ | userId | 1 min | 60 |
| `/objections/:id/sufficiency` | GET | READ | userId | 1 min | 60 |
| `/objections/:id/submit` | POST | SUBMIT | userId | 24 hours | 5 |
| `/objections/:ref/status` | GET | READ | userId | 1 min | 60 |
| `/objections/:ref/probe` | POST | WRITE | userId | 1 hour | 20 |
| `/objections/:ref/escalate` | POST | WRITE | userId | 1 hour | 20 |
| `/objections/:ref/close` | POST | WRITE | userId | 1 hour | 20 |
| `/notifications` | GET | READ | userId | 1 min | 60 |
| `/notifications/:id/read` | POST | WRITE | userId | 1 hour | 20 |
| `/notifications/device-token` | POST | WRITE | userId | 1 hour | 20 |

**40 endpoints. 0 gaps.** (`/objections/:id/documents` removed — renamed to `/objections/:id/evidence`, api orphan audit D-6; `/sufficiency` + `/notifications/*` added, D-2.)

---

## 429 response shape

All six limiters use a shared `handler` function that produces the standard error envelope.

```typescript
import { Request, Response } from 'express'

export function rateLimitHandler(req: Request, res: Response): void {
  const retryAfter = Number(res.getHeader('RateLimit-Reset') ?? 60)
  const windowReset = Math.ceil(retryAfter - Date.now() / 1000)

  res.status(429).json({
    data: null,
    error: {
      code: 'rate_limit_exceeded',
      message: 'Too many requests. Please try again later.',
      details: {
        retryAfterSeconds: Math.max(0, windowReset),
      },
    },
  })
}
```

**HTTP response:**

```
HTTP/1.1 429 Too Many Requests
RateLimit-Limit: 10
RateLimit-Remaining: 0
RateLimit-Reset: <epoch-seconds>
Retry-After: <seconds-until-reset>
Content-Type: application/json
```

```json
{
  "data": null,
  "error": {
    "code": "rate_limit_exceeded",
    "message": "Too many requests. Please try again later.",
    "details": {
      "retryAfterSeconds": 47
    }
  }
}
```

`retryAfterSeconds` is the number of seconds until the window resets — dynamic per request.
Flutter reads this value to show a countdown or a "try again in X seconds" message.

**Note:** The `otp_invalid`, `otp_expired`, `max_attempts_exceeded`, and
`resend_cooldown_active` error codes defined in `docs/twilio-integration.md` also return
HTTP 429 in some cases, but they use different `error.code` values and are issued by the
otp-service handler, not by `express-rate-limit`. The Flutter OTP handler switches on
`error.code` — `rate_limit_exceeded` routes to a generic retry screen; the OTP-specific
codes route to the OTP Expired/Resend screen.

---

## Middleware wiring (shared/rateLimiters.ts)

```typescript
// shared/rateLimiters.ts
import rateLimit from 'express-rate-limit'
import { rateLimitHandler } from './rateLimitHandler'

const SHARED = {
  standardHeaders: 'draft-8' as const,
  legacyHeaders: false,
  handler: rateLimitHandler,
}

export const authLimiter    = rateLimit({ ...SHARED, windowMs: 15*60*1000, max: 10,  keyGenerator: (req) => req.ip ?? 'unknown' })
export const otpVerifyLimiter = rateLimit({ ...SHARED, windowMs: 10*60*1000, max: 10, keyGenerator: (req) => req.body?.phone ?? req.ip ?? 'unknown' })
export const otpSendLimiter   = rateLimit({ ...SHARED, windowMs: 10*60*1000, max:  3, keyGenerator: (req) => req.body?.phone ?? req.ip ?? 'unknown' })
export const searchLimiter    = rateLimit({ ...SHARED, windowMs:    60*1000, max: 10, keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown' })
export const readLimiter      = rateLimit({ ...SHARED, windowMs:    60*1000, max: 60, keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown' })
export const aiEstimateLimiter= rateLimit({ ...SHARED, windowMs:    60*1000, max:  5, keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown' })
export const writeLimiter     = rateLimit({ ...SHARED, windowMs: 60*60*1000, max: 20, keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown' })
export const submitLimiter    = rateLimit({ ...SHARED, windowMs: 24*60*60*1000, max: 5, keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown' })
export const refreshLimiter   = rateLimit({ ...SHARED, windowMs: 15*60*1000, max: 30, keyGenerator: (req) => req.ip ?? 'unknown' })
export const logoutLimiter    = rateLimit({ ...SHARED, windowMs: 15*60*1000, max: 10, keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown' })
```

**Application at router level (example — auth router):**

```typescript
// modules/auth/auth.router.ts
import { authLimiter, refreshLimiter, logoutLimiter } from '../../shared/rateLimiters'

router.post('/login',           authLimiter,    loginHandler)
router.post('/register',        authLimiter,    registerHandler)
router.post('/register/start',  authLimiter,    registerStartHandler)
router.post('/refresh',         refreshLimiter, refreshHandler)
router.post('/logout',          logoutLimiter,  logoutHandler)
router.post('/kyc',             writeLimiter,   kycHandler)
router.get('/session',          readLimiter,    sessionHandler)
```

Rate limiters are applied **before** JWT middleware on public routes (login, register,
register/start, refresh) so that the rate limit fires even for unauthenticated requests with
missing or malformed tokens.

---

## Twilio compatibility verification

| Constraint | Twilio value | Application-layer limit | Compatible? |
|---|---|---|---|
| Max verify attempts per session | 5 (fixed, non-configurable) | OTP-VERIFY: 10/10 min | ✓ Twilio fires first |
| Max resends per session | `OTP_MAX_RESENDS_PER_SESSION = 3` | OTP-SEND: 3/10 min | ✓ Match — middleware enforces same ceiling |
| Resend cooldown | `OTP_RESEND_COOLDOWN_SECONDS = 30 s` | Not a rate-limit concern — enforced by Redis gate in otp-service | ✓ No conflict |

The application-layer rate limit on OTP verify (10/10 min) is looser than Twilio's
5-attempt ceiling — Twilio's enforcement fires first. The application layer prevents
session-reset attacks that bypass Twilio. No conflict. ✓
