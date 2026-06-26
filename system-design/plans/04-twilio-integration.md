# 📱 Twilio OTP Integration

## Background
⛔ BLOCKED[Gate] — requires plans/00-figma-ingest.md CONFIRM task (screen inventory
confirmed by user).

OTP delivery on South African mobile networks (Vodacom, MTN, Cell C, Telkom Mobile)
has real-world latency that differs materially from US or EU benchmarks. Twilio Verify
vs Programmable SMS is not purely a cost decision — it determines how much OTP lifecycle
logic lives in the Node.js service (code generation, storage, expiry, attempt counting)
vs Twilio's infrastructure. Every parameter defined here becomes a Node.js config
constant AND a JSON field in every OTP API response that the Flutter countdown widget
consumes.

## Description
Choose the Twilio product for OTP dispatch. Define every OTP lifecycle parameter. Map
every OTP-related Figma screen transition to a specific Twilio API call. Define
machine-readable error codes the Flutter OTP screen handler will switch on.

## Purpose
To answer: "what happens to the user's session if an OTP SMS is delayed 45 seconds on
a South African mobile network — and whose responsibility is that?" Every parameter
defined here must be motivated by that scenario, not chosen arbitrarily.

## Goal
`easy_rates/system-design/docs/twilio-integration.md` — chosen product with rationale,
lifecycle parameters table, Figma transition → Twilio call map, error-code catalogue,
and South African network latency consideration.

## Tasks

- [x] ✅ THINK `/socratic "What happens to the user's session if an OTP SMS is delayed
  45 seconds on a South African mobile network — and whose responsibility is that?
  At what point does a user give up and call the municipality, and how does our TTL
  and resend policy prevent that?"`
  Done when: the UX failure scenario is described in writing; every lifecycle
  parameter (TTL, max attempts, resend cooldown, max resends) is motivated by that
  scenario — not by a default value copied from a tutorial.
  Downstream: this written scenario becomes the justification paragraph for
  `ttl_seconds` in the DECIDE task — reference it by name ("per the 45-second
  delay scenario") so the parameter value is traceable to the reasoning, not
  chosen arbitrarily.

- [x] ✅ LEARN `/unpack "Twilio Verify API vs Twilio Programmable SMS for OTP —
  what the Node.js service must implement itself in each option, pricing per
  verification for South Africa, Node.js SDK maturity, and what Twilio Verify's
  'check' endpoint returns on success, failure, and expiry"`
  Done when: you can state exactly what the Node.js service must own in each option
  (code generation, Redis storage, expiry check, attempt counting) and the
  cost-per-OTP for a South African number.

- [x] ✅ RESEARCH Find a credible South African SMS delivery latency figure (Twilio
  published data, community reports, or a test). P95 delivery time on ZA networks
  is the floor for the TTL decision — the TTL must be meaningfully larger than the
  P95 delivery time.
  Done when: a ZA delivery latency figure is documented with its source; TTL is
  chosen with explicit margin over that figure.

- [x] ✅ DECIDE Choose Verify API or Programmable SMS. Write a one-paragraph rationale.
  Then set all four lifecycle parameters with a one-line justification each:
  `ttl_seconds` — why this value given ZA network latency?
  `max_invalid_attempts` — why this count before lockout?
  `resend_cooldown_seconds` — why this gap between resend requests?
  `max_resends_per_session` — why this ceiling?
  These become Node.js config constants (environment variables). They also appear as
  integer fields in every OTP API response so the Flutter countdown widget can render
  them without hardcoding values in the client.
  Also decide the Twilio circuit breaker policy: how many consecutive 5xx responses
  (in what time window) open the breaker, and what is the half-open probe interval.
  These become two additional config constants (`TWILIO_CB_THRESHOLD`,
  `TWILIO_CB_RESET_SECONDS`) in the otp-service consumer.
  Done when: product chosen; all four lifecycle parameters set with justifications;
  circuit breaker policy stated; no value is "I'll decide later."

- [x] ✅ MAP Map every OTP-related Figma screen transition to its Twilio call:
  Sign Up → POST /api/v1/otp/send → Twilio Verify: start verification
  Verify OTP (correct) → POST /api/v1/otp/verify → Twilio Verify: check → approved
  Verify OTP (wrong) → POST /api/v1/otp/verify → Twilio Verify: check → pending
  Verify OTP (expired) → POST /api/v1/otp/verify → Twilio Verify: check → expired
  Resend → POST /api/v1/otp/resend → cancel existing + start new verification
  Forgot Password → same OTP flow, different session context
  Done when: every OTP transition in screen-inventory.md has a named Twilio call
  and a named Node.js route handler function.

- [x] ✅ ERRORS Define the error response shape for each OTP failure state. These are
  machine-readable `error.code` values — the Flutter error handler switches on these
  strings, not on HTTP status codes alone:
  `otp_expired` | `otp_invalid` | `max_attempts_exceeded` | `resend_cooldown_active`
  For each: HTTP status, `error.code` string, `error.message` (human-readable),
  `error.details` (e.g. `{ "retry_after_seconds": 60 }` for cooldown).
  Done when: four error codes defined; details payload specified for each.
  Downstream: these four error codes and their exact `details` payload shapes are
  copied verbatim into `easy_rates/system-design/api/otp.md` in plan/09 — they
  must not be redefined or renamed there. The Flutter OTP screen handler switches
  on `error.code` strings; any rename here breaks the client.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/twilio-integration.md` — product
  rationale, lifecycle parameters table, ZA latency note, Figma transition map,
  error-code catalogue.
  Done when: all five sections present; parameter values match what will go into
  Node.js config; error codes match what will go into api/otp-service.md.

- [x] ✅ VERIFY Create a Twilio test account (free tier). Send a test OTP to a South
  African mobile number. Measure the actual delivery time. Confirm it fits within the
  chosen TTL with a reasonable safety margin.
  Done when: real delivery time recorded; TTL confirmed against it; or a credible
  proxy used and documented if a ZA number is not available for testing.

## Recommended skill
▶ `/socratic` ✅ — THINK task; the 45-second delay scenario is the frame that forces
   every parameter to be justified rather than defaulted.
   alt: `/unpack` ✅ — Twilio Verify vs Programmable SMS if the product difference
   is not already clear.

## Engagement Instructions

```bash
# 1. File exists
ls -lh easy_rates/system-design/docs/twilio-integration.md
# Expected: present, size > 3 KB

# 2. Twilio Verify API named as chosen product (per ADR-001)
grep -i "Verify API" easy_rates/system-design/docs/twilio-integration.md | wc -l
# Expected: ≥ 2

# 3. All 4 lifecycle parameters set with numeric values — no TBD
for param in "ttl_seconds" "max_invalid_attempts" \
             "resend_cooldown_seconds" "max_resends_per_session"; do
  printf "%-30s %s\n" "$param:" \
    "$(grep -iE "$param\s*[:=]\s*[0-9]" \
       easy_rates/system-design/docs/twilio-integration.md | head -1)"
done
# Expected: each line shows a parameter with a number, not blank

grep -iE "TBD|decide later|to be determined" \
  easy_rates/system-design/docs/twilio-integration.md
# Expected: 0 results

# 4. ZA network latency figure documented with a source
grep -iE "latency|P95|delivery.*time|[0-9]+\s*ms|South Africa.*ms|Vodacom|MTN" \
  easy_rates/system-design/docs/twilio-integration.md | wc -l
# Expected: ≥ 2 lines (latency value + source reference)

# 5. All 4 machine-readable error codes defined
for code in "otp_expired" "otp_invalid" \
            "max_attempts_exceeded" "resend_cooldown_active"; do
  printf "%-30s %s mentions\n" "$code:" \
    "$(grep -c "$code" easy_rates/system-design/docs/twilio-integration.md)"
done
# Expected: each ≥ 1

# 6. Every OTP Figma transition mapped to a Twilio call
for transition in "start verification\|startVerification" \
                  "check.*approved" "check.*pending" \
                  "check.*expired" "cancel.*resend\|resend"; do
  printf "%-35s %s lines\n" "$transition:" \
    "$(grep -icE "$transition" \
       easy_rates/system-design/docs/twilio-integration.md)"
done
# Expected: each ≥ 1

# 7. Forward consistency: error codes in twilio-integration.md match api/otp.md
# (run after plan/09 completes)
diff \
  <(grep -oE "otp_expired|otp_invalid|max_attempts_exceeded|resend_cooldown_active" \
      easy_rates/system-design/docs/twilio-integration.md | sort -u) \
  <(grep -oE "otp_expired|otp_invalid|max_attempts_exceeded|resend_cooldown_active" \
      easy_rates/system-design/api/otp.md 2>/dev/null | sort -u)
# Expected: no diff output (codes identical in both files)
```

Gate: checks 1–6 must pass before this plan closes.
Check 7 is a deferred cross-plan consistency check — run it once plan/09 is
complete. Any diff means the Flutter client would switch on a code that the
backend never emits, or vice versa.
