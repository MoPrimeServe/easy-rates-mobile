# Gap Report

> **Status: EMPTY of open gaps relative to the canonical contracts.**
> Reconciled 2026-06-27 to the **passwordless** flows (ADR-002). This report is
> now a thin verdict that defers the authoritative cross-check to
> `easy_rates/system-design/api/orphan-audit.md`, which already proves zero
> forward/reverse orphans and 6/6 cross-references against the sealed contracts.

## Source note (reconciliation, 2026-06-27)

The earlier revision of this file mapped a **Forgot Password / Reset-via-OTP**
flow and a `FORGOT_PASSWORD` OTP purpose. **ADR-002 (passwordless) removed all of
that.** There is no password, therefore no forgot-password, no reset, and no
set-new-password screen or route. The stale rows (former T10–T13, the
`POST /auth/forgot-password` and `POST /auth/reset-password` routes, and the
`FORGOT_PASSWORD` purpose) have been **dropped**. `OtpPurpose` is exactly
`REGISTRATION | LOGIN`.

The canonical surface is the eight sealed service contracts under
`easy_rates/system-design/api/` (auth, otp, property, account, bill, objection,
notification, municipality) plus `conventions.md`. The orphan-audit is the
authoritative cross-check artifact; this gap-report does not duplicate it, it
ratifies it.

## Verdict — zero open gaps

Per `system-design/api/orphan-audit.md` (§5, PASS — true zero):

- **Forward orphans: 0** — every Figma screen transition that needs a backend
  call maps to a named route (F-1/F-2/F-3 all closed).
- **Reverse orphans: 0** — every client route maps to a Figma transition;
  `device-token` and the municipality webhook are intentionally screenless
  (infra/internal), outside the Flutter-screen scope.
- **Cross-references: 6/6 pass** — OTP TTL/cooldown, upload size/mime,
  ObjectionStatus and ObjectionCategory enums all match across documents.
- **Cross-document discrepancies: 7/7 resolved** (upstream edits applied).

No backend plan is blocked by an open gap. The gate that 00-ingest-adr guards is
**clear**.

## Canonical passwordless onboarding (replaces the stale forgot-password rows)

| Figma transition | Canonical route | Service | OtpPurpose |
|---|---|---|---|
| App Launch token check | `GET /auth/session` | auth | — |
| Sign Up (start) | `POST /auth/register/start` → internal `POST /otp/send` | auth → otp | REGISTRATION |
| Verify Phone OTP (registration) | `POST /otp/verify` → `registrationToken` | otp | REGISTRATION |
| Complete registration | `POST /auth/register` (consumes token, issues RS256 session) | auth | — |
| Log In (passwordless) | `POST /auth/login` → internal `POST /otp/send` | auth → otp | LOGIN |
| Verify Login OTP | `POST /otp/verify` → token pair | otp | LOGIN |
| Resend OTP | `POST /otp/resend` | otp | REGISTRATION \| LOGIN |
| Refresh (background) | `POST /auth/refresh` | auth | — |
| Log Out | `POST /auth/logout` | auth | — |
| Upload Proof of Address (KYC) | `POST /auth/kyc` | auth | — |

There is **no** forgot-password, reset-password, or set-new-password row — by
design (ADR-002). The OTP is the sole credential; a "forgotten password" is not a
state that can exist.

## The rest of the surface

FIND PROPERTY, BILL REVIEW, EVIDENCE & CHALLENGE, SUBMISSION, TRACKING &
RESOLUTION, ACCOUNT & SETTINGS are all covered by the orphan-audit's forward and
reverse tables (§1, §2) against the sealed contracts. Reproducing them here would
duplicate the source of truth; refer to `orphan-audit.md`.

## Honest caveat (Figma PDF)

No Figma process-flow PDF is present in this environment. The transition labels
the orphan-audit walks are taken from
`system-design/docs/screen-inventory.md` (7 flows, 70 screens), which is itself
derived from the Figma flows and is the committed system-of-record for screen
inventory. The cross-check is therefore against the *committed* screen inventory,
not a live re-render of the PDF. If/when the actual Figma export is supplied,
re-confirm the screen and diamond labels against `screen-inventory.md` — but the
route surface (the thing this gate protects) is sealed and orphan-free
regardless, because routes are checked against the contracts, not the pixels.

## Execution Note — 2026-06-27 (capstone)

Reconciled this report from the stale forgot-password mapping to the canonical
passwordless surface and made it defer to `orphan-audit.md`. The downstream
end-to-end run (`plans/07-flow-walkthrough.md`, Execution Note) then exercised the
canonical onboarding live — `register/start → otp/verify (REGISTRATION) →
register → session`, and `login → otp/verify (LOGIN) → token pair` — with a real
RS256 token, confirming the passwordless flows this report now describes are not
just mapped on paper but actually run. **Verdict: gap-report EMPTY of open gaps.**
