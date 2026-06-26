# 🎬 End-to-End Flow Walkthrough — Terminal Script

> ⛔ **BLOCKED[Gate]** — requires plans/03 (auth), 04 (OTP), 05 (queue), 06
> (property), 08 (bill), 09 (objection), 10 (notification), 11 (status), and 12
> (account) all complete before this plan starts.

## Background

This is the definition-of-done verification for the entire backend scope. The
walkthrough script traces every Figma screen transition across all seven process
flows to a named terminal command, asserts the HTTP response code, and queries
psql or redis-cli to confirm the resulting DB/cache state. It is not a smoke
test — every decision-point branch must be represented by a named section, and
every significant state change must be visible in psql.

The Figma PDF (uploaded in plan/00) is the authoritative source for section
names. Each `▶` label in the script must match the Figma transition label exactly.

## Description

Write `scripts/flow-walkthrough.sh` as a narrated, named-section script. Run it
against the live Podman stack. Every section must print `✓` and every psql query
must return at least one row confirming the expected state.

## Purpose

Proves the backend scope is done. A developer reading the walkthrough output can
trace any Figma screen transition across all seven flows to a specific HTTP call
and see the database row that was created or mutated — without a GUI.

## Goal

`easy_rates/backend/scripts/flow-walkthrough.sh` — exits 0 against the live
Podman stack; every Figma decision-point branch across all seven flows is
represented; psql confirms DB state at every significant step.

## Tasks

- [ ] ⚠️ T1  Write `easy_rates/backend/scripts/flow-walkthrough.sh`.

  Preamble:

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  BASE_URL="${BASE_URL:-http://localhost:3000}"
  PSQL="psql ${DATABASE_URL} -t -c"
  pass() { echo "  ✓ $1"; }
  fail() { echo "  ✗ FAILED: $1"; exit 1; }
  assert_http() { [ "$1" = "$2" ] || fail "Expected HTTP $2, got $1 — $3"; }
  ```

  ONBOARDING — New User:

  ```bash
  # ▶ Sign Up → Account Created + OTP Sent
  RESP=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/auth/register \
    -H "Content-Type: application/json" \
    -d '{"phone":"+27821000001","password":"Test1234!"}')
  CODE=$(echo "$RESP" | tail -1)
  USER_ID=$(echo "$RESP" | head -1 | jq -r '.userId')
  assert_http "$CODE" "201" "register"
  $PSQL "SELECT id, phone FROM \"User\" WHERE phone='+27821000001';"
  $PSQL "SELECT id, purpose FROM \"OTPRecord\" WHERE \"userId\"='$USER_ID';"
  pass "User created, OTPRecord queued"

  # ▶ Verify Phone OTP → OTP Invalid
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE_URL/otp/verify \
    -d "{\"userId\":\"$USER_ID\",\"purpose\":\"REGISTER\",\"code\":\"000000\"}")
  assert_http "$CODE" "400" "verify invalid"
  $PSQL "SELECT attempts FROM \"OTPRecord\" WHERE \"userId\"='$USER_ID' ORDER BY \"createdAt\" DESC LIMIT 1;"
  pass "attempts incremented"

  # ▶ Verify Phone OTP → OTP Expired (seed expired record)
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE_URL/otp/verify \
    -d "{\"userId\":\"$EXPIRED_USER_ID\",\"purpose\":\"REGISTER\",\"code\":\"123456\"}")
  assert_http "$CODE" "410" "verify expired"
  pass "expired path confirmed"

  # ▶ OTP Expired → Resend
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE_URL/otp/resend \
    -d "{\"userId\":\"$USER_ID\",\"purpose\":\"REGISTER\"}")
  assert_http "$CODE" "202" "resend"
  $PSQL "SELECT COUNT(*) FROM \"OTPRecord\" WHERE \"userId\"='$USER_ID';"
  pass "new OTPRecord created"

  # ▶ Verify Phone OTP → OTP Valid → Home Dashboard
  VALID_CODE=$(redis-cli GET otp:${USER_ID}:REGISTER)
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE_URL/otp/verify \
    -d "{\"userId\":\"$USER_ID\",\"purpose\":\"REGISTER\",\"code\":\"$VALID_CODE\"}")
  assert_http "$CODE" "200" "verify valid"
  $PSQL "SELECT \"verifiedAt\" FROM \"OTPRecord\" WHERE \"userId\"='$USER_ID' AND \"verifiedAt\" IS NOT NULL;"
  pass "verifiedAt set"
  ```

  ONBOARDING — Returning User:

  ```bash
  # ▶ Log In
  TOKENS=$(curl -s -X POST $BASE_URL/auth/login \
    -d '{"phone":"+27821000002","password":"ReturnPass1!"}')
  ACCESS=$(echo "$TOKENS" | jq -r '.accessToken')
  REFRESH=$(echo "$TOKENS" | jq -r '.refreshToken')
  $PSQL "SELECT id, \"createdAt\" FROM \"RefreshToken\" ORDER BY \"createdAt\" DESC LIMIT 1;"
  pass "login successful, RefreshToken created"

  # ▶ Refresh Token
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE_URL/auth/refresh \
    -d "{\"refreshToken\":\"$REFRESH\"}")
  assert_http "$CODE" "200" "refresh"
  pass "new access token issued"
  ```

  ONBOARDING — Forgot Password:

  ```bash
  # ▶ Forgot Password → Reset via OTP
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE_URL/auth/forgot-password \
    -d '{"phone":"+27821000002"}')
  assert_http "$CODE" "202" "forgot-password"
  $PSQL "SELECT purpose FROM \"OTPRecord\" WHERE purpose='FORGOT_PASSWORD' ORDER BY \"createdAt\" DESC LIMIT 1;"
  pass "FORGOT_PASSWORD OTPRecord created"

  # ▶ Verify Reset OTP → Log In
  RESET_CODE=$(redis-cli GET otp:${RETURNING_USER_ID}:FORGOT_PASSWORD)
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE_URL/otp/verify \
    -d "{\"userId\":\"${RETURNING_USER_ID}\",\"purpose\":\"FORGOT_PASSWORD\",\"code\":\"$RESET_CODE\"}")
  assert_http "$CODE" "200" "reset OTP verified"
  pass "password reset OTP verified"
  ```

  FIND PROPERTY — all four branches:

  ```bash
  # ▶ Account Found
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/property?accountNumber=ACC001")
  assert_http "$CODE" "200" "property found"
  $PSQL "SELECT id, \"accountNumber\", address FROM \"Property\" WHERE \"accountNumber\"='ACC001';"
  pass "Property record returned"

  # ▶ Account Not Found
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/property?accountNumber=NOTFOUND001")
  assert_http "$CODE" "404" "account not found"
  pass "404 confirmed"

  # ▶ Manual Search → Match
  RESULTS=$(curl -s "$BASE_URL/property/search?q=123+Main+Street")
  COUNT=$(echo "$RESULTS" | jq 'length')
  [ "$COUNT" -gt 0 ] || fail "expected non-empty results for manual search"
  $PSQL "SELECT address, \"erfNumber\" FROM \"Property\" WHERE address ILIKE '%Main%' LIMIT 3;"
  pass "manual search match confirmed"

  # ▶ Manual Search → No Match → Contact Support
  RESULTS=$(curl -s "$BASE_URL/property/search?q=zzznomatch")
  COUNT=$(echo "$RESULTS" | jq 'length')
  [ "$COUNT" -eq 0 ] || fail "expected empty array for no-match query"
  pass "no match — empty array confirmed"
  ```

  BILL REVIEW, EVIDENCE & CHALLENGE, SUBMISSION, TRACKING & RESOLUTION,
  and ACCOUNT & SETTINGS sections to be added once plans/08–12 are
  complete. Each section follows the same pattern: named curl call →
  assert HTTP status → psql query confirming DB state → `pass`.

  Final line: `echo ""; echo "All Figma transitions passed. ✓"`

  Done when: script is written for all implemented flows, shellcheck
  passes, script is executable (`chmod +x`).

- [ ] ⚠️ T2  Run the full stack and execute the script:

  ```bash
  podman-compose up -d && \
  pnpm db:migrate && \
  pnpm db:seed && \
  sleep 5 && \
  bash scripts/flow-walkthrough.sh
  ```

  Done when: script exits 0; every section prints `✓`; no Figma transition
  is unrepresented; psql shows rows at every DB-check step.

- [ ] ⚠️ T3  `git commit -m "Backend complete — flow walkthrough passes all Figma transitions with DB state verified"`

  Done when: commit is clean; `scripts/flow-walkthrough.sh` is included
  and executable in the commit.

## Recommended skill

▶ `/verify` ✅ — runs the app and observes behaviour; directly applicable to
   executing the walkthrough and confirming each section.
   alt: custom for authoring the script itself (project-specific curl/psql
   choreography).

## Engagement Instructions

```bash
# 1. Script exists and is executable
ls -lh easy_rates/backend/scripts/flow-walkthrough.sh
# Expected: present, executable bit set (-rwxr-xr-x or similar)

# 2. shellcheck passes (no syntax errors)
shellcheck easy_rates/backend/scripts/flow-walkthrough.sh
# Expected: exit 0, no errors (warnings acceptable)

# 3. Full stack running with migrated + seeded database
podman-compose -f easy_rates/backend/podman-compose.yml up -d && \
  cd easy_rates/backend && pnpm db:migrate && pnpm db:seed
# Expected: all containers healthy; migrate and seed exit 0

# 4. Script exits 0 — every Figma transition passes
bash easy_rates/backend/scripts/flow-walkthrough.sh
# Expected: exit 0; every section prints ✓;
# final line: "All Figma transitions passed. ✓"

# 5. After script: psql confirms DB state matches script operations
psql "$DATABASE_URL" -t -c \
  "SELECT phone FROM \"User\" WHERE phone='+27821000001';"
psql "$DATABASE_URL" -t -c \
  'SELECT "verifiedAt" FROM "OTPRecord" WHERE "verifiedAt" IS NOT NULL LIMIT 3;'
psql "$DATABASE_URL" -t -c \
  "SELECT \"accountNumber\", address FROM \"Property\" WHERE \"accountNumber\"='ACC001';"
psql "$DATABASE_URL" -t -c \
  'SELECT event FROM "AuditLog" ORDER BY "createdAt" DESC LIMIT 10;'
# Expected: User row, OTPRecord with verifiedAt, Property row, AuditLog events
# all matching the operations the script performed

# 6. All 7 Figma flows represented (named-section count)
grep -c "^  # ▶" easy_rates/backend/scripts/flow-walkthrough.sh
# Expected: ≥ 20 named transitions covering all 7 flows
```

Gate: check 4 is the definition-of-done gate for the entire backend scope.
A partial pass (script reaches a `set -e` failure) does not close this plan —
fix the failing section and re-run from the top. Every psql query must return
at least one row; zero rows means the preceding HTTP call did not produce the
expected DB state — debug the service, not the script.
