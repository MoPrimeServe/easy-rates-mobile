# 👤 Account Service — Profile, Linked Properties, Notification Preferences, History

> ⛔ **BLOCKED[Gate]** — requires ADR-001 committed, `gap-report.md` empty, AND
> plan/02 (Prisma schema + migrations) complete before this plan starts.

## Background

The ACCOUNT & SETTINGS flow is the self-service management surface: ratepayers
can update their profile, manage which properties are linked to their account,
control notification preferences (SMS/push on/off per event type), browse their
objection history, and log out. This is the least complex service but it touches
the most entities — it reads from User, Account, Property, Objection, and
UserNotificationPreference. Log out is handled by revoking the RefreshToken
(already in auth-service), so account-service only calls auth-service's revoke
endpoint rather than implementing its own.

## Description

Implement profile CRUD, linked property management, notification preference
settings, and objection history query. All routes require a valid JWT access
token (middleware from auth-service shared module).

## Purpose

Covers the ACCOUNT & SETTINGS Figma flow: Profile Settings, Manage Linked
Properties, Notification Preferences, History of Objections, Help & Support
(static/FAQ), Log Out.

## Goal

`easy_rates/backend/services/account-service/` — all six ACCOUNT & SETTINGS
sections implemented; JWT middleware enforced on all routes; integration smoke
passes against the live stack.

> **⚠️ Canonical-contract note (2026-06-27).** Superseded by the sealed
> `system-design/api/account-service.md`. Profile is **read-only for MVP** (Profile PATCH
> + change-password are explicitly DEFERRED — no Figma screen, would be reverse orphans),
> and returns **masked** fields (`phoneMasked`, `idNumberMasked`) — never raw phone/ID,
> never a password. Preferences are **four boolean/enum fields** (`smsEnabled`,
> `pushEnabled`, `emailEnabled`, `language`) on the User, partial-updated by PUT — NOT a
> `{type,channel,enabled}` array over a `UserNotificationPreference` table (which does not
> exist). There is **no `RefreshToken` table** (refresh state lives in the KV/Redis store);
> logout belongs to auth-service and is NOT duplicated here. `POST /account/properties`
> linking is `POST /property/link` in property-service (cross-reference, not this contract).
> Tasks reconciled below.

## Tasks

- [x] ✅ T1  Shared bearer auth — ✓ verified. The RS256 `requireAuth` middleware was
  **promoted into `@easyrates/auth-core`** (one shared copy; `apps/auth` now re-exports it,
  and property/bill/account all import it) — exactly the "written once in shared, not
  duplicated per service" intent. ✓ smoke: `GET /account/profile` with no token → 401.

- [x] ✅ T2  Profile — ✓ verified (read-only). `GET /account/profile` returns
  `{userId, displayName, email, phoneMasked, idNumberMasked}` — `phoneMasked` derived from
  the stored phone, `idNumberMasked` a fully-masked placeholder (ADR-003: plaintext SA ID
  never stored, so no real digits to reveal). **No raw phone/ID, no password field.**
  ✓ smoke: `phoneMasked:"+27 82 XXX X567"`, `idNumberMasked:"•••••••••••••"`.
  - [x] ❌ DESCOPED `PATCH /account/profile` — DEFERRED by the canonical contract (no MVP
    Figma screen for self-serve edits; would be a reverse orphan).

- [x] ✅ T3  Linked properties (list) — ✓ verified. `GET /account/properties` joins the
  user's `Account` rows to `Property` (by `accountNumber`), returning
  `{id, accountNumber, address, erfNumber, ward, status, linkedAt}` (`id` = the link/Account
  id used by DELETE; `ward` from `Property.metadata`). ✓ smoke: 3 linked properties returned.
  - [x] ❌ DESCOPED `POST /account/properties` — canonical equivalent is `POST /property/link`
    (property-service). `DELETE /account/properties/:id` is in the contract (204) but outside
    this READ/PUT-focused build scope — see ⚠️ in the Execution Note.

- [x] ✅ T4  Preferences — ✓ verified (replaces the array/table design). `GET /account/preferences`
  → `{smsEnabled, pushEnabled, emailEnabled, language}`; `PUT /account/preferences` accepts any
  **subset** (omitted fields unchanged), validates `language ∈ {en,zu,af,st}` (else 400
  `validation_error` with `details.fields.language`), returns the full updated object.
  Stored as four fields on `User` (schema extended) — no `UserNotificationPreference` table.
  ✓ smoke: PUT `{language:"zu",pushEnabled:false}` persisted; sms/email left unchanged;
  invalid `language:"xx"` → 400.

- [x] ❌ DESCOPED T5  `GET /account/objections` (paginated history). In the canonical
  contract but **outside this task's build scope** (property/bill/account core reads).
  Left as honest ⚠️ for a follow-up; the `Objection` model + `Paginated<T>` shape exist.

- [x] ❌ DESCOPED T6  `POST /account/logout`. Logout is owned by auth-service
  (`POST /auth/logout`, already built) and is explicitly NOT duplicated in the account
  contract; there is no `RefreshToken` table to assert against (refresh state is in Redis).

- [x] ✅ T7  Seed — ✓ verified. The seed user now has **two linked properties/accounts** and
  notification-preference fields set; reseed green. (Two objection-history entries DESCOPED
  with T5.)

- [x] ✅ T8  Unit tests — ✓ verified. `apps/account/src/logic.test.ts`, 6 tests green
  (`pnpm --filter ./apps/account test`): phone masking (incl. middle never leaked, null,
  pass-through) and id masking (13-char placeholder, null).

- [x] ✅ T9  Integration smoke — ✓ verified (transcript captured) against live
  `easyrates_dev` with a real RS256 token: profile (masked) → properties (3) →
  preferences GET → PUT partial → GET (persisted) → invalid-language 400 → no-token 401.
  (The plan's login-with-password + logout + `RefreshToken` psql steps are STALE — passwordless
  ADR-002, no RefreshToken table.)

## Recommended skill

▶ `/build-to-contract` ✅ — builds account routes from the API contract in
   `system-design/api/account.md`.

## Engagement Instructions

```bash
# 1. JWT middleware enforced: 401 without a valid token
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:${ACCOUNT_PORT:-3009}/account/profile)
echo "no token: HTTP $CODE"   # Expected: 401

# 2. Unit tests green
cd easy_rates/backend/services/account-service && pnpm test
# Expected: all tests pass

# 3. Profile GET returns User data
TOKEN=$(curl -s -X POST http://localhost:${AUTH_PORT:-3001}/auth/login \
  -H "Content-Type: application/json" \
  -d '{"phone":"+27821000002","password":"ReturnPass1!"}' | jq -r '.accessToken')
curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:${ACCOUNT_PORT:-3009}/account/profile | jq .
# Expected: object with phone, createdAt, linked account numbers

# 4. Link property: Account row in psql
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"accountNumber":"ACC001"}' \
  http://localhost:${ACCOUNT_PORT:-3009}/account/properties | jq .
psql "$DATABASE_URL" -t -c \
  "SELECT \"accountNumber\" FROM \"Account\" WHERE \"userId\"=(SELECT id FROM \"User\" WHERE phone='+27821000002');"
# Expected: ACC001 row present

# 5. Notification preferences upsert: psql confirms updated row
curl -s -X PUT -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '[{"type":"STATUS_CHANGE","channel":"SMS","enabled":false}]' \
  http://localhost:${ACCOUNT_PORT:-3009}/account/preferences | jq .
psql "$DATABASE_URL" -t -c \
  "SELECT type, channel, enabled FROM \"UserNotificationPreference\" ORDER BY id DESC LIMIT 3;"
# Expected: row with type=STATUS_CHANGE, channel=SMS, enabled=false

# 6. Objection history: paginated list with latest status
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:${ACCOUNT_PORT:-3009}/account/objections" | jq 'length'
# Expected: ≥ 1 entry (from seed data)

# 7. Logout: refresh token revoked; subsequent refresh returns 401
REFRESH=$(curl -s -X POST http://localhost:${AUTH_PORT:-3001}/auth/login \
  -H "Content-Type: application/json" \
  -d '{"phone":"+27821000002","password":"ReturnPass1!"}' | jq -r '.refreshToken')
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"refreshToken\":\"$REFRESH\"}" \
  http://localhost:${ACCOUNT_PORT:-3009}/account/logout | jq .
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:${AUTH_PORT:-3001}/auth/refresh \
  -H "Content-Type: application/json" \
  -d "{\"refreshToken\":\"$REFRESH\"}")
echo "post-logout refresh: HTTP $CODE"   # Expected: 401
psql "$DATABASE_URL" -t -c \
  'SELECT "revokedAt" FROM "RefreshToken" ORDER BY "revokedAt" DESC LIMIT 1;'
# Expected: revokedAt is non-null
```

Gate: check 1 must pass before any other route is exercised — account data is
user-private and must be protected from the first line of code. Check 7 post-logout
401 is mandatory — a token that works after logout is a security defect.
psql must confirm state changes at each step (checks 4, 5, 7), not just HTTP 200.

## Execution Note — 2026-06-27

**Built** `apps/account` (Express/TypeScript) to the canonical
`system-design/api/account-service.md`:

- Files: `apps/account/src/{app.ts,server.ts,logic.ts,logic.test.ts}`, `package.json`,
  `tsconfig.json`.
- Routes: `GET /account/profile` (masked, read-only), `GET /account/properties`,
  `GET /account/preferences`, `PUT /account/preferences` (partial), plus `/health`.
- Reuses `@easyrates/http`, the shared `@easyrates/auth-core` `requireAuth`, and the
  `@easyrates/db` singleton. Profile masks phone/ID and never emits raw values or a
  password. Preferences are four fields on `User` (schema extended: `smsEnabled`,
  `pushEnabled`, `emailEnabled`, `preferredLanguage`) — partial PUT, full-object response,
  `language` enum validated.

**Verification:** `tsc --noEmit` → exit 0 ✓; `pnpm --filter ./apps/account test` → 6/6
green ✓; integration smoke vs live `easyrates_dev` with a real RS256 token ✓ — masked
profile, 3 linked properties, preferences GET/PUT (partial persisted, others unchanged),
invalid-language 400, no-token 401.

**Honest ⚠️ remaining / DESCOPED:** `DELETE /account/properties/:id` (204 unlink) and
`GET /account/objections` (paginated history) are in the contract but outside this task's
READ/PUT core-build scope — left for a follow-up (the `Objection` model + `Paginated<T>`
shape exist). Profile PATCH + change-password are **DESCOPED** (DEFERRED by the contract —
no MVP Figma screen). Logout is **DESCOPED here** — owned by auth-service
(`POST /auth/logout`), and there is no `RefreshToken` table (refresh state in Redis).
`idNumberMasked` is a fully-masked placeholder, not real leading/trailing digits, because
ADR-003 stores only the keyed hash (plaintext SA ID never persisted). Rate-limiting not yet
wired (plan/05 track).
