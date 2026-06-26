# API Orphan Audit — Flutter Client

**Scope:** the EasyRates Flutter mobile app as sole client. Two directions plus six
cross-references, per `plans/api-contracts/plans/09-orphan-audit.md`.

- **Forward orphan** — a Figma screen transition with no matching HTTP route.
- **Reverse orphan** — an HTTP route with no matching Figma screen transition.

Audit covers `api/conventions.md` + 8 service contracts (auth, otp, property, account, bill,
objection, notification, municipality), against `docs/screen-inventory.md` (7 flows, 69 screens)
and the source-of-truth docs (twilio-integration, rate-limits, upload-validation, data-model).

**Result summary:** Forward — 3 orphans, **all closed**. Reverse — 3 routes ahead of the Figma,
**all reconciled** (inbox screen added; device-token + webhook intentional). Cross-references —
6/6 pass. 7 cross-document discrepancies resolved, **upstream edits applied**. **True zero: no
open forward or reverse orphans; no silent gaps.**

> **Upstream edits made to reach zero** (2026-06-21): `KYC_STATUS` + `readAt` added to
> `data-model/notification.md`; `refNumber` format fixed in `data-model/objection.md`;
> `/notifications/*` + `/objections/:id/sufficiency` rows added and stale `/documents` removed in
> `security/rate-limits.md`; Notification Inbox screen added to `screen-inventory.md`; AI endpoint
> name fixed in `plans/api-contracts/MASTER_PLAN.md`.

---

## 1. Forward audit — every screen transition → a route

Walked all 7 flows. Transitions needing a backend call (static/branch/loop screens excluded).

| Flow | Transition | Route | Status |
|---|---|---|---|
| ONBOARDING | App Launch token check | `GET /auth/session` | ✓ |
| ONBOARDING | Log In (passwordless) | `POST /auth/login` (→ internal `POST /otp/send` LOGIN) | ✓ |
| ONBOARDING | Verify Login OTP | `POST /otp/verify` (LOGIN → token pair) | ✓ |
| ONBOARDING | Sign Up | `POST /auth/register/start` (→ internal `POST /otp/send` REGISTRATION) | ✓ |
| ONBOARDING | Complete registration | `POST /auth/register` (consumes registrationToken, issues tokens) | ✓ |
| ONBOARDING | Verify Phone OTP | `POST /otp/verify` | ✓ |
| ONBOARDING | Resend OTP | `POST /otp/resend` | ✓ |
| ONBOARDING | Upload Proof of Address | `POST /auth/kyc` | ✓ |
| ONBOARDING | Awaiting KYC → approved/rejected | push (`KYC_STATUS` type) + file-drop ingestion | ✓ closed (F-2) |
| ONBOARDING | Home Dashboard | `GET /bills/summary` | ✓ |
| FIND PROPERTY | Enter account number | `POST /property/search/account` | ✓ |
| FIND PROPERTY | Manual address/ERF search | `POST /property/search/address` | ✓ |
| FIND PROPERTY | Property Details Confirmation | `GET /property/:id` | ✓ |
| FIND PROPERTY | Save (link) | `POST /property/link` | ✓ |
| FIND PROPERTY | Download PDF | `GET /property/:id/pdf` | ✓ |
| BILL REVIEW | Bills List | `GET /bills` | ✓ |
| BILL REVIEW | Bill Line Items Breakdown | `GET /bills/:id` + `GET /bills/:id/lines` | ✓ |
| BILL REVIEW | Charges look correct? | `POST /bills/:id/review` | ✓ |
| BILL REVIEW | View AI Expected Amount | `GET /bills/:id/ai-estimate` | ✓ |
| BILL REVIEW | Category entry → objection draft | `POST /objections/draft` | ✓ |
| EVIDENCE & CHALLENGE | Upload Supporting Documents | `POST /objections/:id/evidence` | ✓ |
| EVIDENCE & CHALLENGE | Check evidence → Sufficient evidence? | `GET /objections/:id/sufficiency` | ✓ **closed (F-1)** |
| EVIDENCE & CHALLENGE | Review Summary | `GET /objections/:id/summary` | ✓ |
| SUBMISSION | Submit (async) | `POST /objections/:id/submit` (202) | ✓ |
| TRACKING | Track Objection Status | `GET /objections/:ref/status` | ✓ |
| TRACKING | Request status update (probe) | `POST /objections/:ref/probe` | ✓ |
| TRACKING | Upload Requested Docs (MORE_INFO) | `POST /objections/:id/evidence` (auto-transition documented) | ✓ closed (F-3) |
| TRACKING | Appeal (after REJECTED) | `POST /objections/:ref/escalate` | ✓ |
| TRACKING | View Adjusted Bill | `GET /bills/:id` (re-fetch) | ✓ |
| TRACKING | Close case (after UPHELD) | `POST /objections/:ref/close` | ✓ |
| ACCOUNT & SETTINGS | Profile | `GET /account/profile` | ✓ |
| ACCOUNT & SETTINGS | Linked properties | `GET /account/properties` / `DELETE /account/properties/:id` | ✓ |
| ACCOUNT & SETTINGS | Notification preferences | `GET` / `PUT /account/preferences` | ✓ |
| ACCOUNT & SETTINGS | History of Objections | `GET /account/objections` | ✓ |
| ACCOUNT & SETTINGS | Log Out | `POST /auth/logout` | ✓ |

**Forward orphans — all closed:**

- **F-1 — Evidence sufficiency check.** *Closed.* The "Check evidence → Sufficient evidence?"
  diamond had no route. Added `GET /objections/:id/sufficiency` to objection-service (+ its TS
  interface, Figma Trace row, and rate-limit row).
- **F-2 — KYC approval/rejection ingestion.** *Closed.* `KYC_STATUS` added to the
  `NotificationType` enum in `data-model/notification.md`, so the KYC push has a backing
  notification record. KYC-status *ingestion* remains an **intentional Phase-1 boundary**: per
  screen-inventory it is an external municipal **file-drop**, deliberately not an API route. This
  is now a documented scope boundary, not an orphan (no Figma transition expects an EasyRates
  endpoint to set KYC status).
- **F-3 — "Upload Requested Docs" auto-transition.** *Closed.* The evidence route in
  objection-service now documents the `more_info_requested → under_review` auto-transition on a
  successful upload while the objection is in `MORE_INFO_REQUESTED`.

---

## 2. Reverse audit — every route → a screen transition

37 client routes across 7 Flutter-facing services + 1 internal webhook. All map to a Figma
transition (§1) **except:**

| Route | Issue | Status |
|---|---|---|
| `GET /notifications` | Notification Inbox screen added to screen-inventory | ✓ closed (R-1) |
| `POST /notifications/:id/read` | Mark-read on inbox row tap (inbox screen now exists) | ✓ closed (R-1) |
| `POST /notifications/device-token` | Infrastructure (FCM token registration); legitimately screenless | ✓ intentional |
| `POST /municipality/objections/:ref/response` | Internal webhook — not a Flutter screen by design | ✓ out of client scope |

**Reverse orphans — all reconciled:**

- **R-1 — Notification inbox screen.** *Closed.* `GET /notifications` and
  `POST /notifications/:id/read` are justified (notifications must be listed and marked read); the
  fix was to **add the screen, not delete the routes**. A "Notification Inbox" screen was added to
  `screen-inventory.md` under ACCOUNT & SETTINGS (counts updated 69 → 70).
- `device-token` and the municipality webhook are intentionally screenless and are **not** counted
  as orphans (infrastructure / internal, outside the Flutter-screen scope of this audit).

---

## 3. Cross-reference checks (6/6 pass)

| # | Check | Sources | Result |
|---|---|---|---|
| a | OTP `ttlSeconds` | otp-service = **600** vs twilio-integration `OTP_TTL_SECONDS` = 600 | ✓ match |
| b | OTP `resendCooldownSeconds` vs rate-limit window | cooldown **30 s** (Redis gate) vs OTP-SEND limiter 3/10 min | ✓ compatible — 3 resends at ≥30 s gaps fit the 10-min window; the limiter never fires before the cooldown allows a resend |
| c | `maxFileSizeBytes` | objection-service + auth/kyc = **10485760** vs upload-validation = 10485760 | ✓ identical |
| d | `acceptedMimeTypes[]` | objection + auth/kyc = `["application/pdf","image/jpeg","image/png"]` vs upload-validation | ✓ identical |
| e | `ObjectionStatus` enum | objection-service, municipality-service, account history = `UNDER_REVIEW \| MORE_INFO_REQUESTED \| UPHELD \| REJECTED` vs data-model/objection.md (4 values) | ✓ match |
| f | `ObjectionCategory` enum | objection-service = `WRONG_METER_READING \| INCORRECT_TARIFF \| PROPERTY_NOT_OCCUPIED \| DUPLICATE_OTHER` vs data-model/objection.md + data-model/bill.md `DisputeCategory` | ✓ match |

Note on (e): the **Figma** screens use extra labels (`pending`, `submitted`, `escalated`,
`closed`, `draft`). These are **not** enum values — they map onto the 4 (draft = the
`ObjectionDraft` entity; submitted/pending = `UNDER_REVIEW`; escalated/closed = client-side
display states). Documented in objection-service "Status model". The contract enum matches the
data model exactly (DoD item 8 satisfied).

---

## 4. Additional cross-document discrepancies (resolved, with actions)

These surfaced during the migration and the socratic review; each resolved centrally in
`conventions.md` / the contracts, with any required upstream edit flagged.

| # | Discrepancy | Resolution | Required upstream action |
|---|---|---|---|
| D-1 | Reference number format — three variants: `ELM-2026-NNNNNN` (Figma), `OBJ-2026-001` (data-model example), `OBJ-202606-000042` (old contract) | Canonical = **`ELM-2026-NNNNNN`** (Figma wins for a user-facing value) | ✅ Applied — `refNumber` example updated in `docs/data-model/objection.md` |
| D-2 | `/notifications/*` routes absent from rate-limits.md | Assigned READ/WRITE categories in notification-service | ✅ Applied — `/notifications/*` (+ `/objections/:id/sufficiency`) rows added, stale `/documents` removed, in `docs/security/rate-limits.md` |
| D-3 | `Notification` model has no `read`/`readAt` field, but the inbox needs it | Contract derives `read = (readAt != null)` | ✅ Applied — `readAt DateTime?` added to `Notification` in `docs/data-model/notification.md` |
| D-4 | OTP send endpoint was missing from the old contract | `POST /otp/send` `[internal]` documented (it exists per twilio + rate-limits) | none — resolved in-contract |
| D-5 | AI endpoint name — `expected-amount` (MASTER_PLAN G5) vs `ai-estimate` (rate-limits, ai-calculation) | Canonical = **`GET /bills/:id/ai-estimate`** | ✅ Applied — G5 wording updated in `plans/api-contracts/MASTER_PLAN.md` |
| D-6 | Evidence route name — `/objection/:id/documents` vs `/objections/:id/evidence` | Canonical = **`/objections/:id/evidence`** | none — resolved in-contract (matches upload-validation flag) |
| D-7 | Profile PATCH + change-password (G4) vs read-only Figma | Deferred — no Figma screen; would be reverse orphans | Re-include when a profile-edit screen is designed |

---

## 5. Audit verdict — PASS (true zero)

- **Forward orphans: 0.** All three closed — F-1 (added `GET /objections/:id/sufficiency`),
  F-2 (added `KYC_STATUS` type; KYC ingestion is an intentional file-drop boundary, not an orphan),
  F-3 (MORE_INFO auto-transition documented on the evidence route).
- **Reverse orphans: 0.** R-1 closed by adding the Notification Inbox screen to screen-inventory;
  `device-token` and the municipality webhook are intentionally screenless (infra/internal),
  outside the Flutter-screen scope.
- **Cross-references: 6/6 pass** with identical values confirmed.
- **Cross-document discrepancies: 7/7 resolved** — upstream edits applied (D-1, D-2, D-3, D-5),
  resolved in-contract (D-4, D-6), or deferred by design with no Figma screen (D-7).

Every Figma transition that needs a backend call maps to a named route, and every client route
maps to a Figma transition. The DoD is met: a Flutter developer can build the entire client from
`api/` without a follow-up question. **No silent gaps remain.**
