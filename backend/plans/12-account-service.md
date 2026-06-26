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

## Tasks

- [ ] ⚠️ T1  Apply JWT auth middleware to all account-service routes. Import the
  shared `verifyAccessToken` middleware from `shared/auth.ts` (to be written
  once in shared — not duplicated per service).
  Done when: any account route returns 401 when called without a valid token.

- [ ] ⚠️ T2  `GET /account/profile` — return User record fields (phone, createdAt,
  linked account numbers). `PATCH /account/profile` — update display name or
  notification contact (phone update requires OTP re-verification — out of scope
  here; return 501 with a clear message).
  Done when: GET returns user data; PATCH updates non-sensitive fields.

- [ ] ⚠️ T3  `GET /account/properties` — return all Property records linked to the
  authenticated user via Account. `POST /account/properties` — link a new
  property by accountNumber (calls property-service to validate it exists).
  `DELETE /account/properties/:accountNumber` — unlink.
  Done when: curl GET returns linked properties; POST links a new one; DELETE
  unlinks; psql confirms Account rows after each operation.

- [ ] ⚠️ T4  `GET /account/preferences` — return `UserNotificationPreference` rows
  for the user. `PUT /account/preferences` — bulk-update: accept an array of
  `{ type, channel, enabled }` and upsert records via Prisma.
  Done when: GET returns preferences; PUT upserts; psql confirms updated rows.

- [ ] ⚠️ T5  `GET /account/objections` — return paginated Objection history for the
  user, ordered by `createdAt` desc; include latest status from
  `ObjectionStatusHistory`. Accept optional `?status=` filter.
  Done when: curl returns objection list with latest status; filter works.

- [ ] ⚠️ T6  Log Out — `POST /account/logout`: call auth-service's
  `POST /auth/revoke` with the refresh token from the request body;
  return 200. (Auth-service owns token revocation; account-service delegates.)
  Done when: curl logout → refresh token revoked → subsequent refresh returns 401.

- [ ] ⚠️ T7  Seed data for ACCOUNT & SETTINGS Figma branches (add to `prisma/seed.ts`):
  - User with two linked properties
  - User with notification preferences set (SMS off, push on)
  - User with two objection history entries (one SUBMITTED, one UPHELD)
  Done when: `pnpm db:seed` runs; psql confirms UserNotificationPreference +
  Account rows for the seed user.

- [ ] ⚠️ T8  Unit tests: profile GET/PATCH, link property (valid account, unknown
  account → 404), unlink, preferences GET/PUT, objection history (with and without
  filter), logout.
  Done when: `pnpm test` passes in account-service directory.

- [ ] ⚠️ T9  Integration smoke: login → GET /account/profile → POST /account/properties
  (link) → GET /account/properties → PUT /account/preferences → GET /account/objections
  → POST /account/logout → confirm refresh token revoked.
  Done when: full lifecycle passes; psql confirms state at each step.

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
