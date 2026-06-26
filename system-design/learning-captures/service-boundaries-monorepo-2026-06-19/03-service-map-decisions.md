# Service Map Decisions

**Source:** ASSIGN, SYNC-ASYNC, and WRITE task execution. Output: `easy_rates/system-design/docs/service-map.md`.

---

## Nine locked module names

| Service | Node.js Module | Primary concern |
|---|---|---|
| auth-service | `src/modules/auth` | Identity, sessions, KYC, password reset |
| otp-service | `src/modules/otp` | OTP generation, delivery, verification |
| property-service | `src/modules/property` | Property search, identity-gated linking |
| account-service | `src/modules/account` | User profile, linked properties, preferences |
| bill-service | `src/modules/bill` | Bill data, line items, AI-estimate, mark-as-correct |
| objection-service | `src/modules/objection` | Objection draft, evidence, submission lifecycle |
| notification-service | `src/modules/notification` | Email, SMS, push dispatch |
| status-service | `src/modules/status` | Objection status tracking, probes, escalation |
| queue-consumer | `src/modules/queue-consumer` | Background worker — no Flutter screens |

These names are immutable across plans 03, 06, 07, 08, 09, 10. Any rename requires updating every reference.

---

## Three cross-service synchronous calls

These are the only places one module calls another as a function during a request. All other cross-module communication is async via queue-consumer.

| Caller | Callee | Function | Data | Why sync |
|---|---|---|---|---|
| auth-service | otp-service | `otp.verifyOtp(phone, code)` | `{ phone, code }` | Password reset / phone verification cannot issue a result until OTP is confirmed valid. Transaction gate. |
| objection-service | bill-service | `bill.getCharge(chargeId)` | `{ charge_id, bill_id }` | Objection draft cannot be created without charge label, amount, billing period. Required at insert time. |
| objection-service | status-service | `status.transition(objectionId, status)` | `{ objection_id, status: 'pending' }` | Status must transition atomically with document upload confirmation. Flutter cannot show correct state until complete. |

---

## Five async queue tasks (plan/03 seeds)

| Queue Task | Triggered by | Consumed by | When |
|---|---|---|---|
| `otp.dispatch` | auth-service | otp-service | Sign-up, forgot-password, OTP resend |
| `notification.kyc_status_change` | auth-service (municipality webhook) | notification-service | `kyc_status` → `kyc_approved` or `kyc_rejected` |
| `notification.objection_submitted` | objection-service | notification-service | `Objection.status` → `submitted` |
| `notification.objection_status_change` | status-service | notification-service | Status → `more_info_requested`, `upheld`, or `rejected` |
| `notification.probe_escalation` | status-service | notification-service | 3rd probe submitted |

---

## Hop-count results (all flows ≤ 2 hops)

| Flow | Hops | Services |
|---|---|---|
| ONBOARDING — Log In | 1 | auth |
| ONBOARDING — Sign Up + Phone Verify | 2 | auth → otp (verify) |
| ONBOARDING — Forgot Password + Reset | 2 | auth → otp (verify) |
| FIND PROPERTY — Account Number search | 1 | property |
| BILL REVIEW — View Bill + Dispute | 2 | bill → objection (draft) |
| EVIDENCE & CHALLENGE — Submit Objection | 2 | objection → bill (getCharge at draft) |
| TRACKING & RESOLUTION — Upload Requested Docs | 2 | status → objection (transition) |

No flow exceeds two synchronous hops. No design smells.
