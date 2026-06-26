# Twilio OTP Integration
Generated: 2026-06-20

This document is the single source of truth for all OTP delivery decisions. Every
parameter value here becomes a Node.js environment variable AND an integer field in
every OTP API response. The Flutter countdown widget reads parameters from the server;
nothing is hardcoded client-side. The error codes in section 5 are copied verbatim into
`api/otp.md` — they must not be renamed in that file or in the Flutter handler.

---

## 1. Product Choice: Twilio Verify API

**Chosen product: Twilio Verify API** (not Programmable SMS).

Verify is the right choice for three compounding reasons. First, the WhatsApp fallback
channel — the only bearer-independent fallback for South African network conditions,
where WhatsApp travels over data while the SMSC is congested — is natively supported in
the Verify API; Programmable SMS would require a separate WhatsApp Business API
integration, doubling the delivery layer surface. Second, Verify's built-in attempt
counting, rate limiting, and code storage eliminate the Redis OTP keys entirely, which
maps cleanly to the EasyRates service boundary: the Node.js otp-service owns error
handling, not OTP state management. Third, Emfuleni's self-service login volume is
low-frequency (monthly billing interactions, not session-per-hour social traffic); at
that volume the $0.05 USD per successful verification premium over Programmable SMS is
not a cost driver. The fixed 5-attempt ceiling in Verify matches the
`OTP_MAX_INVALID_ATTEMPTS` parameter below without requiring a workaround.

**Cost reference (South Africa, August 2025 rates):**

| Option | Per SMS sent | Per successful verification | Approx. cost/verified user (1 attempt) |
|---|---|---|---|
| Programmable SMS | $0.1089 | — | $0.1089 |
| Twilio Verify API | ≈ $0.1089 (channel fee) | $0.05 | ≈ $0.159 |

The Verify channel fee for South Africa is not published separately on the Verify pricing
page; the $0.1089 figure is estimated from the Programmable SMS ZA rate. Confirm via
the Twilio pricing calculator with a +27 number before finalising the cost model.

**Node.js ownership with Verify API:**

| Responsibility | Verify API | otp-service owns |
|---|---|---|
| Code generation | Twilio | — |
| Code storage | Twilio | — |
| TTL enforcement | Twilio | — |
| Attempt counting | Twilio (max 5, fixed) | — |
| Built-in rate limiting | Twilio | — |
| Expiry error handling | — | catch `err.code === 60200` |
| Max-attempts error handling | — | catch `err.code === 60202` |
| Resend count tracking | — | Redis `otp_attempts:${phone}` |
| SID storage for cancel-on-resend | — | Redis `otp_sid:${phone}` |
| Application-layer rate limiting | — | `OTP_RESEND_COOLDOWN_SECONDS` gate |

---

## 2. Lifecycle Parameters

All six values are environment variables in the otp-service container. All four OTP
lifecycle parameters (`OTP_*`) are returned as integer fields in every OTP API response
body so the Flutter client never hardcodes them.

| Constant | Value | Unit | Justification |
|---|---|---|---|
| `OTP_TTL_SECONDS` | `600` | seconds | ZA SMSC delays reach 45 s under congestion; load-shedding can compound this. The effective user window (TTL minus delivery, read, and input time) must remain positive in the worst case. 600 s (Verify's maximum) provides a 530 s margin over the 70 s worst-case consumption and keeps the attack window acceptable on this low-threat-model system. |
| `OTP_MAX_INVALID_ATTEMPTS` | `5` | attempts | Verify enforces 5 as a fixed, non-configurable limit. This tolerates OCR errors and fat-finger input on small prepaid handsets while limiting brute-force exposure. Matches industry norms for OTP protection. |
| `OTP_RESEND_COOLDOWN_SECONDS` | `30` | seconds | 30 s gives the initial SMS time to clear transient SMSC queues (median ZA delivery is well under 30 s) while keeping the wait short enough that a stressed ratepayer does not abandon before the button appears. Unlocks at t = 30 s of a 600 s window. |
| `OTP_MAX_RESENDS_PER_SESSION` | `3` | resends | 3 resends caps per-session SMS cost at 4 messages (≈ $0.44 ZA) before surfacing the WhatsApp fallback, covers realistic scenarios (one SMSC delay plus one user retry), and limits send-endpoint abuse. |
| `TWILIO_CB_THRESHOLD` | `3` | consecutive 5xx in 60 s | One 5xx is a transient fault; two may be coincidence; three consecutive within 60 seconds is a pattern indicating a genuine Twilio degradation. The 60-second window prevents stale failures from contributing to the count. When open, otp-service returns a structured error immediately — no Twilio call attempted. |
| `TWILIO_CB_RESET_SECONDS` | `30` | seconds | Twilio minor incidents typically resolve within 2–15 minutes. A 30 s half-open probe interval detects recovery quickly without hammering a degraded service. Success closes the breaker; failure re-opens it and resets the 30 s wait. |

**.env reference — copy these to otp-service configuration:**

```
OTP_TTL_SECONDS=600
OTP_MAX_INVALID_ATTEMPTS=5
OTP_RESEND_COOLDOWN_SECONDS=30
OTP_MAX_RESENDS_PER_SESSION=3
TWILIO_CB_THRESHOLD=3
TWILIO_CB_RESET_SECONDS=30
```

---

## 3. South African Network Latency

**Design figure: 45-second worst-case SMSC delay.**

South African carriers (Vodacom, MTN, Cell C, Telkom Mobile) route SMS through a Short
Message Service Centre (SMSC). Under network congestion — peak traffic periods,
community social spikes, or cell tower battery depletion during load-shedding — messages
queue in the SMSC and delivery latency can reach 45 seconds at the tail. This is the
figure used to derive `OTP_TTL_SECONDS`.

**Effective user window derivation:**

```
effective_window = OTP_TTL_SECONDS
                - worst_case_delivery_seconds   (45 s — SMSC congestion, ZA networks)
                - read_time_seconds             (15 s — low-literacy user, small screen)
                - input_time_seconds            (10 s)
                = 600 - 45 - 15 - 10
                = 530 s
```

530 seconds of effective window after all delays. A 60-second TTL (common tutorial
default) would leave only 5 seconds and produce auth failures that look like user error
but are engineering failures.

**Load-shedding amplification:** During Stage 4–6 load-shedding, cell tower backup
batteries deplete over hours. At late-stage battery depletion, both SMS (SMSC path) and
data (WhatsApp path) may degrade simultaneously. No software parameter rescues a dead
network; the offline cache and intent-state preservation (see
`docs/screen-inventory.md` — OTP Expired/Resend screen) are the only tools at that
point.

**Source note:** The 45-second delay figure is derived from ZA network behaviour analysis
conducted during system design (June 2026). A formal P95 delivery time measurement
against a live South African number is pending (VERIFY task in `plans/04-twilio-integration.md`).
The TTL must be re-confirmed against that measurement. MTN and Vodacom do not publish
SMSC latency SLAs publicly.

---

## 4. Figma Screen Transition Map

Three Node.js handler functions cover all OTP-related screen transitions.
`context` is stored in Redis at `otp_session:${phone}` when `sendOtp` is called;
`verifyOtp` reads it to determine the post-approval action without a request parameter.

### Handler: `sendOtp` — `POST /otp/send`

Twilio call: `client.verify.v2.services(serviceSid).verifications.create({ to: phone, channel: 'sms' })`

Side effects: stores `{ verificationSid, context, resendCount: 0 }` in Redis at
`otp_sid:${phone}` with EX 600.

| From screen | Triggering event | To screen | Context |
|---|---|---|---|
| Sign Up | `POST /auth/register/start` (phone not yet registered) | OTP Sent (registration) → Verify Phone OTP | `phone_verification` |
| Log In | `POST /auth/login` (phone registered) | Verify Login OTP | `login` |

### Handler: `verifyOtp` — `POST /otp/verify`

Twilio call: `client.verify.v2.services(serviceSid).verificationChecks.create({ to: phone, code: userInput })`

Must be wrapped in try/catch. Context read from Redis to determine post-approval action.

| From screen | Twilio response | HTTP | To screen | Action |
|---|---|---|---|---|
| Verify Phone OTP | `status: 'approved'` (REGISTRATION) | 200 | OTP Valid? → Valid → `POST /auth/register` → Upload Proof of Address | Return single-use `registrationToken` (no session yet); clear `otp_sid:${phone}` |
| Verify Phone OTP | `status: 'pending'` — check returned pending | 422 | OTP Valid? → Invalid → OTP Expired/Resend | Return `otp_invalid` error + lifecycle params |
| Verify Phone OTP | throws `err.code 60200` — check expired | 410 | OTP Valid? → Invalid → OTP Expired/Resend | Return `otp_expired` error + lifecycle params |
| Verify Phone OTP | throws `err.code 60202` — max attempts exceeded | 429 | OTP Valid? → Invalid → OTP Expired/Resend | Return `max_attempts_exceeded` error + lifecycle params |
| Verify Login OTP | `status: 'approved'` (LOGIN) | 200 | Home Dashboard | Issue the session token pair (accessToken + refreshToken); clear `otp_sid:${phone}` |
| Verify Login OTP | throws `err.code 60200` — check expired | 410 | OTP Expired / Resend | Return `otp_expired` error + lifecycle params |
| Verify Login OTP | throws `err.code 60202` — max attempts exceeded | 429 | OTP Expired / Resend | Return `max_attempts_exceeded` error + lifecycle params |

### Handler: `resendOtp` — `POST /otp/resend`

Twilio calls (sequential):
1. `client.verify.v2.services(serviceSid).verifications(storedSid).update({ status: 'canceled' })` — cancel existing
2. `client.verify.v2.services(serviceSid).verifications.create({ to: phone, channel: 'sms' })` — start new verification

Pre-checks (before any Twilio call):
- `resendCount < OTP_MAX_RESENDS_PER_SESSION` — else 429
- Elapsed since last send ≥ `OTP_RESEND_COOLDOWN_SECONDS` — else `resend_cooldown_active`

Cancellation is explicit (via stored SID) to prevent two live codes existing simultaneously.

| From screen | Triggering event | To screen | Context |
|---|---|---|---|
| Verify Phone OTP | Resend link tapped (after 30 s cooldown) | Verify Phone OTP — new code dispatched | `phone_verification` |
| OTP Expired / Resend | "Resend OTP" CTA tapped | Verify Phone OTP / Verify Login OTP — new code dispatched | original purpose |
| Verify Login OTP | Resend link tapped (after 30 s cooldown) | Verify Login OTP — new code dispatched | `login` |

### Complete transition index

| # | From screen | Trigger | Route | Handler | Twilio call | Twilio result |
|---|---|---|---|---|---|---|
| 1 | Sign Up | register/start | POST /otp/send | `sendOtp` | `verifications.create` | `status: pending` — start verification |
| 2 | Log In | login submitted | POST /otp/send | `sendOtp` | `verifications.create` | `status: pending` — start verification |
| 3 | Verify Phone OTP | Correct code | POST /otp/verify | `verifyOtp` | `verificationChecks.create` | `status: approved` — check approved |
| 4 | Verify Phone OTP | Wrong code | POST /otp/verify | `verifyOtp` | `verificationChecks.create` | `status: pending` — check pending |
| 5 | Verify Phone OTP | Expired code | POST /otp/verify | `verifyOtp` | `verificationChecks.create` throws | `err.code 60200` — check expired |
| 6 | Verify Phone OTP | Max attempts | POST /otp/verify | `verifyOtp` | `verificationChecks.create` throws | `err.code 60202` |
| 7 | Verify Phone OTP | Resend tapped | POST /otp/resend | `resendOtp` | `verifications.update` → `verifications.create` | cancel + start verification |
| 8 | OTP Expired / Resend | Resend CTA | POST /otp/resend | `resendOtp` | `verifications.update` → `verifications.create` | cancel + start verification |
| 9 | Verify Login OTP | Correct code | POST /otp/verify | `verifyOtp` | `verificationChecks.create` | `status: approved` — check approved |
| 10 | Verify Login OTP | Expired code | POST /otp/verify | `verifyOtp` | `verificationChecks.create` throws | `err.code 60200` — check expired |
| 11 | Verify Login OTP | Max attempts | POST /otp/verify | `verifyOtp` | `verificationChecks.create` throws | `err.code 60202` |
| 12 | Verify Login OTP | Resend tapped | POST /otp/resend | `resendOtp` | `verifications.update` → `verifications.create` | cancel + start verification |

---

## 5. Error-Code Catalogue

These four codes are the authoritative definitions. They are copied verbatim into
`api/otp.md`. The Flutter OTP screen handler switches on `error.code` strings. Any
rename here breaks the client.

**Error response envelope (all four errors):**

```json
{
  "error": {
    "code": "<string>",
    "message": "<string>",
    "details": { }
  }
}
```

---

### `otp_expired`

**Trigger:** `verifyOtp` catches `err.code === 60200` from `verificationChecks.create`.  
**HTTP status:** `410 Gone`

```json
{
  "error": {
    "code": "otp_expired",
    "message": "Your verification code has expired. Please request a new one.",
    "details": {
      "ttl_seconds": 600
    }
  }
}
```

`ttl_seconds` is read from `OTP_TTL_SECONDS` env var. Flutter uses it for the expiry
copy: "Codes expire after 10 minutes." Flutter routes to the OTP Expired / Resend screen.

---

### `otp_invalid`

**Trigger:** `verifyOtp` receives `status: 'pending'`, `valid: false` — wrong code,
attempts still remaining.  
**HTTP status:** `422 Unprocessable Entity`

```json
{
  "error": {
    "code": "otp_invalid",
    "message": "Incorrect code. Please try again.",
    "details": {
      "attempts_remaining": 3,
      "max_attempts": 5
    }
  }
}
```

`attempts_remaining` is dynamic. otp-service maintains `otp_attempts:${phone}` in Redis
(incremented on each `otp_invalid`, TTL matching `OTP_TTL_SECONDS`). Twilio does not
return a remaining-attempts count; the server tracks it locally. Flutter renders
"X attempts remaining" inline on the OTP entry screen.

---

### `max_attempts_exceeded`

**Trigger:** `verifyOtp` catches `err.code === 60202` from `verificationChecks.create`.  
**HTTP status:** `429 Too Many Requests`

```json
{
  "error": {
    "code": "max_attempts_exceeded",
    "message": "Too many incorrect attempts. Please request a new code.",
    "details": {
      "max_attempts": 5
    }
  }
}
```

Flutter routes to the OTP Expired / Resend screen (same destination as `otp_expired`).
The different code allows the client to render the correct copy: "too many attempts"
vs "code expired."

---

### `resend_cooldown_active`

**Trigger:** `resendOtp` called before `OTP_RESEND_COOLDOWN_SECONDS` have elapsed since
the last send.  
**HTTP status:** `429 Too Many Requests`  
**Header:** `Retry-After: <retry_after_seconds>` (standard 429 convention)

```json
{
  "error": {
    "code": "resend_cooldown_active",
    "message": "Please wait before requesting another code.",
    "details": {
      "retry_after_seconds": 18
    }
  }
}
```

`retry_after_seconds` is the **remaining** cooldown, not the total:
`OTP_RESEND_COOLDOWN_SECONDS - elapsed_since_last_send`. Flutter's resend countdown
widget renders this value directly. When it reaches zero, the resend button unlocks
without a page reload.

---

### Error-code summary

| `error.code` | HTTP | `details` fields | Flutter action |
|---|---|---|---|
| `otp_expired` | 410 | `ttl_seconds: int` | Route to OTP Expired / Resend screen |
| `otp_invalid` | 422 | `attempts_remaining: int`, `max_attempts: int` | Show inline "X attempts remaining" |
| `max_attempts_exceeded` | 429 | `max_attempts: int` | Route to OTP Expired / Resend screen |
| `resend_cooldown_active` | 429 | `retry_after_seconds: int` | Drive resend countdown widget |

---

## Open Issues

**1. Screen-inventory resend cooldown discrepancy — RESOLVED 2026-06-21.**
`docs/screen-inventory.md` previously showed "Resend link (enabled after 60 s)" on the OTP
entry screens (now "Verify Phone OTP" and "Verify Login OTP"). The decided value is
`OTP_RESEND_COOLDOWN_SECONDS = 30`; the screen-inventory copy has been corrected to 30 s on
both rows and the Flutter countdown reads the value from the API response.

**2. Max-resends-exceeded state has no error code.**
When `resendCount >= OTP_MAX_RESENDS_PER_SESSION (3)`, the screen inventory routes to
the support CTA ("After 3 resends: show support contact CTA instead of Resend"). Flutter
needs a signal to swap the resend button for the support CTA. This requires either a
fifth error code (`max_resends_exceeded`) or a `resends_remaining` field added to the
`resendOtp` success response. Resolve before `api/otp.md` is written in plan/09.

**3. ZA latency P95 measurement pending.**
The 45-second delay figure is a worst-case design estimate. A formal P95 delivery
measurement against a live South African number is pending (VERIFY task in
`plans/04-twilio-integration.md`). Confirm `OTP_TTL_SECONDS` against that measurement
when available.
