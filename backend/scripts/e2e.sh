#!/usr/bin/env bash
#
# EasyRates mobile customer-journey end-to-end smoke test.
#
# Walks the FULL Figma journey against the live gateway (http://localhost:8080)
# using only curl + python3, asserting every step (✓/✗) and printing a final
# "E2E: N/N passed". Exits non-zero on any failure.
#
# PRECONDITION: the stack is already up in mock mode:  pnpm dev:mock
# (mock mode makes the otp-service log the plaintext OTP and return it as
# `mockCode` from /otp/resend — no real SMS, no Twilio.)
#
# OTP capture (two strategies, log preferred):
#   1. If E2E_LOG points at the file you redirected `pnpm dev:mock` into, the
#      script reads the line `[otp][mock] code for <phone> (<PURPOSE>): <code>`
#      from a remembered offset — the code from the REAL register/start / login
#      send (most faithful).
#   2. Otherwise it falls back to the public POST /otp/resend, which returns
#      `mockCode` in mock mode. (Resend has a 30s cooldown once a live record
#      exists, so the fallback fires only when no log is available.)
#
# Re-runnable: a fresh timestamped registration phone each run; dev-only
# rate-limit keys are reset at start (the AUTH limiter is IP-scoped 10/15min and
# one journey spends ~3 of those — repeated runs would otherwise trip it; the
# reset is justified for a LOCAL MOCK stack only and is a no-op without redis-cli).
# The objection draft falls through line items so a prior run's submitted
# objection doesn't block this one; the seed user has 8 line items, so after
# enough runs refresh the fixture with `pnpm db:seed` (it resets the harness's
# objections, keeping only the canonical ELM-2026-000001).
#
# Deliberately OUT OF SCOPE (documented, not tested): Forgot-Password
# (passwordless OTP-only, ADR-002 — no password to reset), WhatsApp onboarding,
# payments. None of these exist in the backend.
#
set -euo pipefail

BASE="${BASE:-http://localhost:8080/api/v1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEED_PHONE="${SEED_PHONE:-+27821234567}"   # seeded user (owns properties/bills)
SEED_ACCOUNT="${SEED_ACCOUNT:-10045821}"   # seeded service account (8 digits)
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../.env}"
E2E_LOG="${E2E_LOG:-}"                       # combined dev:mock log, if available
REDIS_CLI="$(command -v redis-cli || true)"
SCRATCH="$(mktemp -d)"

PASS=0; TOTAL=0; FAILED=0
trap 'rm -rf "$SCRATCH"' EXIT

# ---- assertion helpers -----------------------------------------------------
# check "<label>" <actual> <expected> "<json body>" "<py-expr on d>"
check() {
  local label="$1" actual="$2" expected="$3" body="${4:-}" expr="${5:-}"
  TOTAL=$((TOTAL + 1))
  if [ "$actual" != "$expected" ]; then
    echo "  ✗ ${label} — expected HTTP ${expected}, got ${actual}"
    echo "      body: $(printf '%s' "$body" | head -c 300)"
    FAILED=$((FAILED + 1)); return 1
  fi
  if [ -n "$expr" ]; then
    if ! printf '%s' "$body" | python3 -c "import sys,json
d=json.load(sys.stdin)
assert ($expr)" 2>/dev/null; then
      echo "  ✗ ${label} — HTTP ${expected} ok but body check failed: ${expr}"
      echo "      body: $(printf '%s' "$body" | head -c 300)"
      FAILED=$((FAILED + 1)); return 1
    fi
  fi
  echo "  ✓ ${label}"; PASS=$((PASS + 1)); return 0
}

# req <METHOD> <path> [<data>] [<bearer>] [<extra curl args...>]  → $STATUS, $BODY
req() {
  local method="$1" path="$2" data="${3:-}" auth="${4:-}"
  shift; shift; shift 2>/dev/null || true; shift 2>/dev/null || true
  local args=(-s -w '\n%{http_code}' -X "$method" "${BASE}${path}")
  [ -n "$auth" ] && args+=(-H "Authorization: Bearer ${auth}")
  [ -n "$data" ] && args+=(-H 'content-type: application/json' -d "$data")
  args+=("$@")
  local out; out="$(curl "${args[@]}")"
  STATUS="${out##*$'\n'}"; BODY="${out%$'\n'*}"
}

# jget "<json>" "<py-expr on d>" → value (empty on miss)
jget() { printf '%s' "$1" | python3 -c "import sys,json
try:
  d=json.load(sys.stdin); print($2)
except Exception:
  print('')"; }

log_lines() { { [ -n "$E2E_LOG" ] && [ -f "$E2E_LOG" ] && wc -l < "$E2E_LOG"; } 2>/dev/null || echo 0; }

# get_mock_code <phone> <PURPOSE> <since_line> — log first, resend fallback.
get_mock_code() {
  local phone="$1" purpose="$2" since="${3:-0}" code=""
  # Escape regex metacharacters in the phone (the leading '+' especially).
  local phone_re; phone_re="$(printf '%s' "$phone" | sed -E 's/[.[\*^$+?(){}|]/\\&/g')"
  if [ -n "$E2E_LOG" ] && [ -f "$E2E_LOG" ]; then
    local i
    for i in $(seq 1 40); do
      code="$(tail -n +"$((since + 1))" "$E2E_LOG" 2>/dev/null \
        | grep -E "code for ${phone_re} \(${purpose}\)" | tail -1 \
        | sed -E 's/.*: ([0-9]{6}).*/\1/' || true)"
      [ -n "$code" ] && { printf '%s' "$code"; return 0; }
      sleep 0.25
    done
  fi
  # Fallback (no log): the public /otp/resend returns `mockCode` in mock mode.
  # A send already happened (register/start or login), so resend may be inside
  # the 30s cooldown — honour the returned retryAfterSeconds once, then retry.
  local out
  for _ in 1 2; do
    out="$(curl -s -X POST "${BASE}/otp/resend" \
      -H 'content-type: application/json' \
      -d "{\"phone\":\"${phone}\",\"purpose\":\"${purpose}\"}")"
    code="$(jget "$out" "d.get('data',{}).get('mockCode','') if d.get('data') else ''")"
    [ -n "$code" ] && { printf '%s' "$code"; return 0; }
    local wait; wait="$(jget "$out" "d.get('error',{}).get('details',{}).get('retryAfterSeconds',0) if d.get('error') else 0")"
    [ -z "$wait" ] && wait=0
    [ "$wait" -le 0 ] 2>/dev/null && return 0
    echo "    (resend cooldown — waiting ${wait}s for a fresh mock code; set E2E_LOG to skip this)" >&2
    sleep "$((wait + 1))"
  done
  printf '%s' "$code"
}

# Reset dev-only rate-limit + stale otp keys so the run is re-runnable.
reset_rate_limits() {
  [ -z "$REDIS_CLI" ] && return 0
  "$REDIS_CLI" --scan --pattern 'ratelimit:*' 2>/dev/null | xargs -r "$REDIS_CLI" del >/dev/null 2>&1 || true
  "$REDIS_CLI" del "otp:${SEED_PHONE}" >/dev/null 2>&1 || true
}

# Write a minimal but VALID 1x1 PNG to $1 (file-type magic-byte detection rejects
# a bare signature — the server validates real PNG structure, not the header).
write_png() {
  python3 - "$1" <<'PY'
import sys, struct, zlib
def chunk(t, d):
    c = t + d
    return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
data = (b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(b"\x00\xff\xff\xff"))
        + chunk(b"IEND", b""))
open(sys.argv[1], "wb").write(data)
PY
}

# Luhn-valid 13-digit SA ID (distinct from the seed holder's ID).
gen_id_number() {
  python3 - <<'PY'
base="850715800108"
s=0
for i,ch in enumerate(reversed(base)):
    d=int(ch)
    if i%2==0:
        d*=2
        if d>9: d-=9
    s+=d
print(base+str((10-(s%10))%10))
PY
}

# Load MUNICIPAL_WEBHOOK_SECRET from env (preferred) or ../.env. Never echoed.
load_webhook_secret() {
  [ -n "${MUNICIPAL_WEBHOOK_SECRET:-}" ] && return 0
  if [ -f "$ENV_FILE" ]; then
    MUNICIPAL_WEBHOOK_SECRET="$(grep -E '^MUNICIPAL_WEBHOOK_SECRET=' "$ENV_FILE" | head -1 \
      | cut -d= -f2- | sed -E 's/^["'"'"']//; s/["'"'"']$//')"
    export MUNICIPAL_WEBHOOK_SECRET
  fi
}

echo "EasyRates E2E — base=${BASE}"
echo "Stack must be up via: pnpm dev:mock"
[ -n "$E2E_LOG" ] && echo "OTP source: log file ${E2E_LOG}" || echo "OTP source: /otp/resend mockCode (set E2E_LOG for log-based capture)"
reset_rate_limits

############################################################################
echo; echo "── 1. ONBOARDING (register a brand-new user) ──────────────────────────"
############################################################################
# Fresh, re-runnable SA E.164 number: +27 followed by exactly 9 digits.
REG_PHONE="+277$(date +%s | tail -c 9)"
ID_NUMBER="$(gen_id_number)"

LB="$(log_lines)"
req POST /auth/register/start "{\"phone\":\"${REG_PHONE}\"}"
check "register/start → 202 (OTP dispatched)" "$STATUS" 202 "$BODY" \
  "d['data']['ttlSeconds']==600 and d['error'] is None"

REG_CODE="$(get_mock_code "$REG_PHONE" REGISTRATION "$LB")"
[ -n "$REG_CODE" ] || { echo "  ✗ could not obtain registration mockCode"; FAILED=$((FAILED+1)); }

req POST /otp/verify "{\"phone\":\"${REG_PHONE}\",\"code\":\"${REG_CODE}\"}"
check "otp/verify (REGISTRATION) → 200 + registrationToken" "$STATUS" 200 "$BODY" \
  "bool(d['data']['registrationToken'])"
REG_TOKEN="$(jget "$BODY" "d['data']['registrationToken']")"

req POST /auth/register \
  "{\"phone\":\"${REG_PHONE}\",\"displayName\":\"E2E Ratepayer\",\"email\":\"e2e${REG_PHONE#+}@example.co.za\",\"idNumber\":\"${ID_NUMBER}\",\"registrationToken\":\"${REG_TOKEN}\"}"
check "register → 201 + session tokens" "$STATUS" 201 "$BODY" \
  "bool(d['data']['accessToken']) and bool(d['data']['refreshToken'])"
NEW_ACCESS="$(jget "$BODY" "d['data']['accessToken']")"
NEW_REFRESH="$(jget "$BODY" "d['data']['refreshToken']")"

req GET /auth/session "" "$NEW_ACCESS"
check "auth/session (new user) → 200 (kycStatus PENDING)" "$STATUS" 200 "$BODY" \
  "d['data']['kycStatus']=='PENDING'"

printf '%%PDF-1.4\n%%E2E proof of address\n' > "$SCRATCH/proof.pdf"
out="$(curl -s -w '\n%{http_code}' -X POST "${BASE}/auth/kyc" \
  -H "Authorization: Bearer ${NEW_ACCESS}" -F "file=@$SCRATCH/proof.pdf;type=application/pdf")"
STATUS="${out##*$'\n'}"; BODY="${out%$'\n'*}"
check "auth/kyc (PDF) → 201 (kycStatus SUBMITTED)" "$STATUS" 201 "$BODY" \
  "d['data']['kycStatus']=='SUBMITTED'"

req POST /auth/refresh "{\"refreshToken\":\"${NEW_REFRESH}\"}"
check "auth/refresh → 200 (rotated tokens)" "$STATUS" 200 "$BODY" \
  "bool(d['data']['accessToken']) and bool(d['data']['refreshToken'])"
ROT_REFRESH="$(jget "$BODY" "d['data']['refreshToken']")"
ROT_ACCESS="$(jget "$BODY" "d['data']['accessToken']")"

req POST /auth/logout "{\"refreshToken\":\"${ROT_REFRESH}\"}" "$ROT_ACCESS"
check "auth/logout → 200" "$STATUS" 200 "$BODY" "d['data']['message']=='Logged out.'"

############################################################################
echo; echo "── Log in as the SEEDED ratepayer (owns properties / bills) ───────────"
############################################################################
reset_rate_limits
LB="$(log_lines)"
req POST /auth/login "{\"phone\":\"${SEED_PHONE}\"}"
check "login (seed) → 200 (anti-enumeration body)" "$STATUS" 200 "$BODY" \
  "'an OTP has been sent' in d['data']['message']"

LOGIN_CODE="$(get_mock_code "$SEED_PHONE" LOGIN "$LB")"
[ -n "$LOGIN_CODE" ] || { echo "  ✗ could not obtain login mockCode"; FAILED=$((FAILED+1)); }

req POST /otp/verify "{\"phone\":\"${SEED_PHONE}\",\"code\":\"${LOGIN_CODE}\"}"
check "otp/verify (LOGIN) → 200 + session" "$STATUS" 200 "$BODY" \
  "bool(d['data']['accessToken'])"
ACCESS="$(jget "$BODY" "d['data']['accessToken']")"

############################################################################
echo; echo "── 2. FIND PROPERTY ───────────────────────────────────────────────────"
############################################################################
req POST /property/search/account "{\"accountNumber\":\"${SEED_ACCOUNT}\"}" "$ACCESS"
check "property/search/account → 200 (property found)" "$STATUS" 200 "$BODY" \
  "d['data']['property'] is not None and d['data']['property']['accountNumber']=='${SEED_ACCOUNT}'"
PROPERTY_ID="$(jget "$BODY" "d['data']['property']['id']")"

req POST /property/search/address "{\"q\":\"Vereeniging\"}" "$ACCESS"
check "property/search/address → 200 (array)" "$STATUS" 200 "$BODY" "isinstance(d['data'], list)"

req GET "/property/${PROPERTY_ID}" "" "$ACCESS"
check "property/:id → 200 (detail)" "$STATUS" 200 "$BODY" "d['data']['id']=='${PROPERTY_ID}'"

############################################################################
echo; echo "── 3. BILL REVIEW ─────────────────────────────────────────────────────"
############################################################################
req GET /bills "" "$ACCESS"
check "bills list → 200 (non-empty)" "$STATUS" 200 "$BODY" "len(d['data'])>=1"
BILL_ID="$(jget "$BODY" "next((b['id'] for b in d['data'] if b['accountNumber']=='${SEED_ACCOUNT}'), d['data'][0]['id'])")"

req GET "/bills/${BILL_ID}" "" "$ACCESS"
check "bills/:id → 200 (detail)" "$STATUS" 200 "$BODY" "d['data']['id']=='${BILL_ID}'"

req GET "/bills/${BILL_ID}/lines" "" "$ACCESS"
check "bills/:id/lines → 200 (line items)" "$STATUS" 200 "$BODY" "len(d['data']['lineItems'])>=1"

# Gather EVERY line item across ALL of the caller's bills (anomaly-flagged first)
# so the draft step can fall through to one that isn't already disputed — keeps
# the script re-runnable even after a previous run consumed a line item.
req GET /bills "" "$ACCESS"
ALL_LINE_IDS=""
for bid in $(jget "$BODY" "' '.join(b['id'] for b in d['data'])"); do
  req GET "/bills/${bid}/lines" "" "$ACCESS"
  ids="$(jget "$BODY" "' '.join([li['id'] for li in d['data']['lineItems'] if li.get('anomalyFlag')] + [li['id'] for li in d['data']['lineItems'] if not li.get('anomalyFlag')])")"
  ALL_LINE_IDS="${ALL_LINE_IDS} ${ids}"
done

req GET "/bills/${BILL_ID}/ai-estimate" "" "$ACCESS"
check "bills/:id/ai-estimate → 200" "$STATUS" 200 "$BODY" "'confidence' in d['data']"

############################################################################
echo; echo "── 4. EVIDENCE & CHALLENGE ────────────────────────────────────────────"
############################################################################
# Draft against the first line item that has no SUBMITTED objection yet. The
# route returns 409 when a submitted objection already covers a charge; we fall
# through to the next candidate so the journey survives prior runs.
OBJECTION_ID=""
DRAFT_OK=0
for LINE_ITEM_ID in $ALL_LINE_IDS; do
  [ -z "$LINE_ITEM_ID" ] && continue
  req POST /objections/draft \
    "{\"lineItemIds\":[\"${LINE_ITEM_ID}\"],\"category\":\"WRONG_METER_READING\",\"notes\":\"The meter reading on this bill is far higher than my actual usage this period.\"}" \
    "$ACCESS"
  if [ "$STATUS" = "200" ]; then
    OBJECTION_ID="$(jget "$BODY" "d['data']['objectionId']")"
    DRAFT_OK=1
    break
  fi
done
TOTAL=$((TOTAL + 1))
if [ "$DRAFT_OK" = "1" ] && [ -n "$OBJECTION_ID" ]; then
  echo "  ✓ objections/draft → 200 (DRAFT) on line ${LINE_ITEM_ID}"; PASS=$((PASS + 1))
else
  echo "  ✗ objections/draft — no draftable line item (all already disputed?)"
  echo "      last body: $(printf '%s' "$BODY" | head -c 200)"
  FAILED=$((FAILED + 1))
fi

write_png "$SCRATCH/meter.png"
out="$(curl -s -w '\n%{http_code}' -X POST "${BASE}/objections/${OBJECTION_ID}/evidence" \
  -H "Authorization: Bearer ${ACCESS}" -F "file=@$SCRATCH/meter.png;type=image/png" -F "label=Meter photo")"
STATUS="${out##*$'\n'}"; BODY="${out%$'\n'*}"
check "objections/:id/evidence (PNG) → 201" "$STATUS" 201 "$BODY" "d['data']['mimeType']=='image/png'"

req GET "/objections/${OBJECTION_ID}/sufficiency" "" "$ACCESS"
check "objections/:id/sufficiency → 200" "$STATUS" 200 "$BODY" "'sufficient' in d['data']"

############################################################################
echo; echo "── 5. SUBMISSION ──────────────────────────────────────────────────────"
############################################################################
req GET "/objections/${OBJECTION_ID}/summary" "" "$ACCESS"
check "objections/:id/summary → 200" "$STATUS" 200 "$BODY" \
  "d['data']['objectionId']=='${OBJECTION_ID}' and len(d['data']['disputedItems'])>=1"

req GET "/objections?pageSize=100" "" "$ACCESS"
REFS_BEFORE="$(jget "$BODY" "' '.join(i['refNumber'] for i in d['data']['items'])")"

req POST "/objections/${OBJECTION_ID}/submit" "" "$ACCESS"
check "objections/:id/submit → 202 (async job)" "$STATUS" 202 "$BODY" \
  "bool(d['data']['jobId']) and 'status' in d['data']['statusUrl']"

OBJECTION_REF=""
for _ in $(seq 1 40); do
  req GET "/objections?pageSize=100" "" "$ACCESS"
  OBJECTION_REF="$(printf '%s' "$BODY" | python3 -c "
import sys,json
before=set('''${REFS_BEFORE}'''.split())
items=json.load(sys.stdin)['data']['items']
new=[i['refNumber'] for i in items if i['refNumber'] not in before]
print(new[0] if new else '')")"
  [ -n "$OBJECTION_REF" ] && break
  sleep 0.4
done
TOTAL=$((TOTAL + 1))
if [ -n "$OBJECTION_REF" ]; then
  echo "  ✓ async worker assigned refNumber ${OBJECTION_REF}"; PASS=$((PASS + 1))
else
  echo "  ✗ async worker did not assign a refNumber in time"; FAILED=$((FAILED + 1))
fi

############################################################################
echo; echo "── 6. TRACKING & RESOLUTION ───────────────────────────────────────────"
############################################################################
req GET /objections "" "$ACCESS"
check "objections (list) → 200" "$STATUS" 200 "$BODY" "d['data']['total']>=1"

req GET "/objections/${OBJECTION_REF}/status" "" "$ACCESS"
check "objections/:ref/status → 200 (UNDER_REVIEW)" "$STATUS" 200 "$BODY" \
  "d['data']['status']=='UNDER_REVIEW' and d['data']['refNumber']=='${OBJECTION_REF}'"

load_webhook_secret
if [ -z "${MUNICIPAL_WEBHOOK_SECRET:-}" ]; then
  echo "  ✗ MUNICIPAL_WEBHOOK_SECRET not set (export it or provide ${ENV_FILE})"
  TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1))
else
  req POST "/municipality/objections/${OBJECTION_REF}/response" \
    "{\"status\":\"MORE_INFO_REQUESTED\",\"note\":\"Please supply a clearer meter photo for verification.\",\"resolvedBy\":\"clerk-e2e\",\"idempotencyKey\":\"e2e-mir-$(date +%s)-$RANDOM\"}" \
    "" -H "X-Municipal-Webhook-Secret: ${MUNICIPAL_WEBHOOK_SECRET}"
  check "municipality webhook MORE_INFO_REQUESTED → 200" "$STATUS" 200 "$BODY" \
    "d['data']['status']=='MORE_INFO_REQUESTED' and d['data']['notificationQueued'] is True"

  write_png "$SCRATCH/meter2.png"
  out="$(curl -s -w '\n%{http_code}' -X POST "${BASE}/objections/${OBJECTION_ID}/evidence" \
    -H "Authorization: Bearer ${ACCESS}" -F "file=@$SCRATCH/meter2.png;type=image/png")"
  STATUS="${out##*$'\n'}"; BODY="${out%$'\n'*}"
  check "re-upload evidence (auto → UNDER_REVIEW) → 201" "$STATUS" 201 "$BODY" \
    "d['data']['mimeType']=='image/png'"

  req GET "/objections/${OBJECTION_REF}/status" "" "$ACCESS"
  check "status back to UNDER_REVIEW after re-upload" "$STATUS" 200 "$BODY" \
    "d['data']['status']=='UNDER_REVIEW'"

  req POST "/municipality/objections/${OBJECTION_REF}/response" \
    "{\"status\":\"UPHELD\",\"note\":\"Meter photo confirms the over-estimate. Charge reduced to the corrected consumption.\",\"adjustedAmount\":\"310.00\",\"resolvedBy\":\"clerk-e2e\",\"idempotencyKey\":\"e2e-upheld-$(date +%s)-$RANDOM\"}" \
    "" -H "X-Municipal-Webhook-Secret: ${MUNICIPAL_WEBHOOK_SECRET}"
  check "municipality webhook UPHELD (+adjustment) → 200" "$STATUS" 200 "$BODY" \
    "d['data']['status']=='UPHELD'"

  req GET "/objections/${OBJECTION_REF}/status" "" "$ACCESS"
  check "status UPHELD with municipalityResponse" "$STATUS" 200 "$BODY" \
    "d['data']['status']=='UPHELD' and d['data']['municipalityResponse']['adjustedAmount']=='310.00'"

  req POST "/objections/${OBJECTION_REF}/close" "" "$ACCESS"
  check "objections/:ref/close → 200 (closed)" "$STATUS" 200 "$BODY" "d['data']['closed'] is True"
fi

############################################################################
echo; echo "── 7. ACCOUNT & SETTINGS + NOTIFICATIONS ──────────────────────────────"
############################################################################
req GET /account/profile "" "$ACCESS"
check "account/profile → 200 (masked)" "$STATUS" 200 "$BODY" "bool(d['data']['phoneMasked'])"

req GET /account/properties "" "$ACCESS"
check "account/properties → 200 (linked properties)" "$STATUS" 200 "$BODY" \
  "isinstance(d['data'], list) and len(d['data'])>=1"

req GET /account/preferences "" "$ACCESS"
check "account/preferences GET → 200" "$STATUS" 200 "$BODY" "'smsEnabled' in d['data']"

req PUT /account/preferences "{\"smsEnabled\":true,\"pushEnabled\":true,\"emailEnabled\":false,\"language\":\"en\"}" "$ACCESS"
check "account/preferences PUT → 200" "$STATUS" 200 "$BODY" \
  "d['data']['emailEnabled'] is False and d['data']['language']=='en'"

req GET "/notifications?pageSize=10" "" "$ACCESS"
check "notifications list → 200" "$STATUS" 200 "$BODY" "'items' in d['data']"
NOTIF_ID="$(jget "$BODY" "d['data']['items'][0]['id'] if d['data']['items'] else ''")"

req POST /notifications/device-token "{\"deviceToken\":\"e2e-fcm-$(date +%s)\",\"platform\":\"ANDROID\"}" "$ACCESS"
check "notifications/device-token → 200" "$STATUS" 200 "$BODY" "d['data']['registered'] is True"

if [ -n "$NOTIF_ID" ]; then
  req POST "/notifications/${NOTIF_ID}/read" "" "$ACCESS"
  check "notifications/:id/read → 200" "$STATUS" 200 "$BODY" "d['data']['read'] is True"
fi

req POST /notifications/read-all "" "$ACCESS"
check "notifications/read-all → 200" "$STATUS" 200 "$BODY" "'updatedCount' in d['data']"

############################################################################
echo; echo "───────────────────────────────────────────────────────────────────────"
if [ "$FAILED" -eq 0 ]; then
  echo "E2E: ${PASS}/${TOTAL} passed"
  exit 0
else
  echo "E2E: ${PASS}/${TOTAL} passed — ${FAILED} FAILED"
  exit 1
fi
