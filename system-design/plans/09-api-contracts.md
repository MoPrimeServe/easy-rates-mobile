# 📡 API Contracts

## Background
⛔ BLOCKED[Gate] — requires plans/01-service-boundaries.md VERIFY task (service names
and endpoint placeholders finalised in service-map.md).
⛔ BLOCKED[Gate] — requires plans/06-data-model.md VERIFY task (model field tables
complete — response field shapes derive directly from model fields).
⛔ BLOCKED[Gate] — requires plans/07-security-design.md VERIFY task (auth model, rate
limits, and upload constraints confirmed — these are non-optional contract fields).

The API contracts are the interface between the Node.js backend and Flutter. They must
be precise enough that a Flutter developer can write Dio models, interceptors, and
error handlers against them without asking a single follow-up question. Any field left
undefined, any error code left unnamed, and any missing rate-limit note is a question
the Flutter developer will have to ask later — blocking them.

## Description
Write the HTTP API contracts for every service. Establish shared conventions first.
Write one contract file per service. Add Figma trace sections. Run a full orphan audit.

## Purpose
To answer: "if a Flutter developer reads only the api/*.md files and nothing else,
can they build the complete mobile client without asking a single question?" Every
field must be present because a Flutter widget renders it. No speculative fields.
No missing error codes.

## Goal
`easy_rates/system-design/api/conventions.md` + one `api/<service>.md` per service —
all routes, request/response schemas derived from data-model.md, error codes, rate-limit
notes, Figma traces, and a passing orphan audit.

## Tasks

- [x] ✅ — ✓ verified (10 "questions a Flutter dev would still ask" produced, each closed by a
  specific cited contract element; landed as the `## 0. Unanswered Questions (resolved)` checklist
  near the top of api/conventions.md — envelope biconditional, switch-on-error.code, §4 details.fields,
  §6 refresh interceptor, §9 decimal-string money/UTC dates, §7 `Paginated<T>`, §8 statusUrl polling,
  §10 camelCase, masked fields, ai-estimate null/isStale/503. Full THINK answer in Execution Note below.)
  THINK `/socratic "If a Flutter developer reads only the api/*.md files and
  nothing else, what questions would they still need to ask you — and how does each
  one of those questions become a change to the contracts before we finalise them?"`
  Done when: a list of "questions a Flutter dev would ask" is produced and each is
  answered by a specific addition to the contracts (a field, an error code, a
  rate-limit note, a pagination format).
  Downstream: the "questions a Flutter dev would still ask" list becomes the opening
  "Unanswered Questions" checklist in conventions.md — each item must be resolved by
  a specific field, error code, or convention addition before the first service contract
  file is opened. An unanswered question surviving into a service contract means a
  Flutter developer will eventually block on it.

- [x] ✅ — ✓ verified (TS interface-vs-type, Zod 400 `details.fields` body, camelCase serialisation,
  and Dio model consumption answered substantively and grounded in conventions.md §2/§4/§10/§12; full
  LEARN answer in Execution Note below.)
  LEARN `/unpack "TypeScript API contract patterns — interface vs type for
  response shapes, Zod schema validation and how validation errors map to HTTP 400
  response bodies with field-level errors, camelCase field serialisation in Node.js,
  and how a Dio model class in Flutter consumes a typed JSON response"`
  Done when: you can write the TypeScript interface for any contract in this plan,
  and you know exactly what a Zod validation-error body looks like so the Flutter
  form-error handler can parse it.

- [x] ✅ — ✓ verified (sub-scope plans/api-contracts/ COMPLETE: all 10 sub-plans ✅, all 8
  MASTER_PLAN DoD items ✅, 79 checked / 0 unchecked. conventions.md present (13K) + 8 service
  contracts present. 42 routes defined across contracts (≥31 baseline ✓). Every contract has ≥4
  TS interfaces. OTP error-code diff vs twilio-integration.md = NO DIFF. OTP lifecycle terms
  (ttl/cooldown/resend/attempt) present in both twilio-integration.md and otp-service.md. Upload
  constraints maxFileSizeBytes/acceptedMimeTypes present in both docs/security/upload-validation.md
  and objection-service.md. orphan-audit.md verdict = PASS true-zero (0 forward, 0 reverse, 6/6
  cross-refs). Note: parent-plan Engagement grep patterns 3/5/7 are stale — they assume `^METHOD /api`
  line-start routes and the old docs/twilio-integration.md + docs/security.md paths; the real
  contracts use `## \`METHOD /path\`` / `## Route:` headers and the source-of-truth docs are
  twilio-integration.md + docs/security/upload-validation.md. Verified against the real locations.)
  WRITE Write `easy_rates/system-design/api/` service contracts — conventions,
  all 9 service contracts, TypeScript interfaces, Figma traces, and orphan audit.
      → decomposed: see `plans/api-contracts/MASTER_PLAN.md`
  Done when: all 9 service contracts in plans/api-contracts/ are complete,
  orphan audit passes for the Flutter client, and api/conventions.md is the shared
  root all contracts conform to.

## Recommended skill
▶ `/socratic` ✅ — THINK task; "what would the Flutter dev still need to ask" is
   the definitive completeness test for any API contract.
   alt: `/unpack` ✅ — TypeScript interface patterns and Zod schema validation if
   the Node.js contract-first approach is unfamiliar.

## Engagement Instructions

```bash
# 1. conventions.md exists (must be written before any service contract)
ls -lh easy_rates/system-design/api/conventions.md
# Expected: present, size > 1 KB

# 2. All 8 service contract files exist (filenames corrected 2026-06-22 sync:
#    api/<svc>-service.md; municipality replaces the old "status"; the AI
#    expected-amount endpoint is embedded in bill-service.md; orphan-audit.md is
#    the audit, checked separately).
for svc in "auth" "otp" "property" "account" "bill" \
           "objection" "notification" "municipality"; do
  printf "%-20s %s\n" "${svc}-service.md:" \
    "$(ls easy_rates/system-design/api/${svc}-service.md 2>/dev/null \
       && echo present || echo MISSING)"
done
# Expected: all present

# 3. OTP lifecycle values match twilio-integration.md exactly
for field in "ttlSeconds\|ttl_seconds" \
             "resendCooldownSeconds\|resend_cooldown" \
             "maxInvalidAttempts\|max_invalid_attempts" \
             "maxResends\|max_resends"; do
  TW=$(grep -icE "$field" easy_rates/system-design/docs/twilio-integration.md)
  OTP=$(grep -icE "$field" easy_rates/system-design/api/otp-service.md 2>/dev/null || echo 0)
  printf "%-40s twilio: %s | otp.md: %s\n" "$field:" "$TW" "$OTP"
done
# Expected: each field appears in both files

# 4. OTP error codes match twilio-integration.md (cross-plan check from plan/04)
diff \
  <(grep -oE "otp_expired|otp_invalid|max_attempts_exceeded|resend_cooldown_active" \
      easy_rates/system-design/docs/twilio-integration.md | sort -u) \
  <(grep -oE "otp_expired|otp_invalid|max_attempts_exceeded|resend_cooldown_active" \
      easy_rates/system-design/api/otp-service.md 2>/dev/null | sort -u)
# Expected: no diff output (codes identical in both files)

# 5. File upload constraints match security.md
for field in "maxFileSizeBytes\|max.*file.*size" \
             "acceptedMimeTypes\|accepted.*mime\|allowed.*type"; do
  SEC=$(grep -icE "$field" easy_rates/system-design/docs/security.md)
  OBJ=$(grep -icE "$field" easy_rates/system-design/api/objection-service.md 2>/dev/null || echo 0)
  printf "%-45s security.md: %s | objection.md: %s\n" "$field:" "$SEC" "$OBJ"
done
# Expected: each field appears in both files

# 6. Every service contract has a TypeScript interface block
for svc in auth otp property account bill objection notification municipality; do
  printf "%-15s %s\n" "${svc}-service.md:" \
    "$(grep -cE "^(export )?interface |^(export )?type [A-Z]" \
       easy_rates/system-design/api/${svc}-service.md 2>/dev/null)"
done
# Expected: each ≥ 1 (at least one TypeScript interface per contract)

# 7. Orphan audit — route count meets gap-report baseline
ROUTE_COUNT=$(grep -cE "^(GET|POST|PUT|PATCH|DELETE) /api" \
  easy_rates/system-design/api/*.md 2>/dev/null || echo 0)
echo "API routes defined: $ROUTE_COUNT"
# Expected: ≥ 31 (per gap-report.md baseline)
```

Gate: checks 1–6 must pass before plan/10 (ADR) may close. ✅ resolved — verified against the
real contract structure (`## \`METHOD /path\`` / `## Route:` headers) and the real source-of-truth
docs (twilio-integration.md, docs/security/upload-validation.md); the literal grep patterns in
checks 3/5/7 are stale but the underlying conditions all hold.
Check 7 is the orphan audit baseline — must reach ≥ 31 routes before backend
implementation (plans/03–06) may start. ✅ resolved — 42 routes defined (≥31). Any mismatch in
check 4 breaks the Flutter OTP screen handler immediately; treat it as a blocking defect.
✅ resolved — check 4 (OTP error-code) diff = NO DIFF.

---

## Execution Note — 2026-06-27

All three tasks executed and verified. The WRITE task's sub-scope (`plans/api-contracts/`) was
already complete; this note records the THINK and LEARN answers (the downstream of the THINK
answer — the resolved checklist — was added as `## 0. Unanswered Questions (resolved)` to
`api/conventions.md`).

### THINK (verbatim) — questions a Flutter dev would still ask, each closed by a contract element

The completeness test for an API contract is: *if a Flutter dev reads only `api/*.md`, is there
any question left that blocks a screen?* I produced the realistic list and closed each against a
specific, already-present contract element. (These ten are the ones that became the resolved
checklist at the top of conventions.md.)

1. **"On an error, is `data` absent or `null`? What does my generated model branch on?"**
   → §2 envelope **biconditional**: `data == null` iff `error != null`; `data` is *never absent*;
   an empty success returns `"data": {}` (never `null`, never a bodiless `204`). So
   `ApiResponse<T>.fromJson` decides its branch from the body alone — `error == null` ⇒ parse
   `data` as `T`. Without this rule the dev would have to special-case empty successes and read
   HTTP status.

2. **"Three different `429`s and two `401`s exist — do I switch on HTTP status?"**
   → §2 + §3: switch on **`error.code`**, never the HTTP status. `rate_limit_exceeded` vs
   `max_attempts_exceeded` vs `resend_cooldown_active` all return `429`; the generic limiter and
   otp-service issue different codes. The contract makes `error.code` the closed switch key.

3. **"How do I paint inline form errors from a 400?"**
   → §4 `validation_error` shape: `details.fields` is a map of field-name → first message, with
   dot-joined paths for nested fields (`address.city`). The Flutter form handler maps each key
   onto its form field. Without the documented shape the dev would guess (array? object? full
   message list?).

4. **"What exactly does my Dio interceptor do when any call returns 401?"**
   → §6 the **401 → `POST /auth/refresh` → retry-once** contract: refresh token is opaque,
   single-use (rotated every refresh), 30-day, in `flutter_secure_storage`; access token RS256
   15-min, in memory only. On refresh `200`: store both, retry original once. On refresh `401`:
   clear both, go to Login (reuse revokes the family). This is the one interceptor the dev builds
   blind otherwise.

5. **"Is money a JSON number? Will floats round my rand amounts?"**
   → §9: money is a **decimal string** (`"1250.00"`), parsed with `Decimal.parse` (package
   `decimal`), never `double`; always 2 fraction digits, ZAR. Dates/datetimes are ISO-8601 UTC
   strings parsed with `DateTime.parse`. Without this, a `double` parse silently corrupts billing
   amounts.

6. **"How do I page a list and know when I've reached the end?"**
   → §7 `Paginated<T>`: `items` (always an array), `page`, `pageSize`, `total`, `totalPages`;
   request `?page=<n>&pageSize=<n>` (1-indexed), request `page+1` while `page < totalPages`;
   defaults `page=1`/`pageSize=20`, max `pageSize=100`. Closes "what's the list wrapper shape and
   the stop condition."

7. **"Objection submit returns `202` — what do I poll and until when?"**
   → §8 `AsyncJob` (`jobId`, `statusUrl`) + objection-service `GET /objections/:ref/status`.
   On `202` show a processing state and poll `statusUrl` until a terminal `ObjectionStatus`
   (`UPHELD`/`REJECTED`); the enum is published in objection-service so the dev knows the terminal
   set.

8. **"Is it `bill_id` or `billId`? Do I hand-write the model?"**
   → §10 + §12: all JSON keys are **camelCase** (`billId`, `accountNumber`, `aiExpectedAmount`);
   snake_case appears *only* inside `error.code`. Models are **generated** from each contract's
   TypeScript-interface block (`freezed`/`json_serializable`), never hand-written, and
   `json['key']` is never accessed outside generated code — the only place a silent casing-`null`
   could enter.

9. **"I need to show the user's phone and ID — does the API send the full value or do I mask it?"**
   → The contracts return **pre-masked** fields: account-service `phoneMasked`
   (`"+27 82 XXX X234"`) and `idNumberMasked` (`"8•••••••••••89"`), auth-service `maskedPhone`
   (`"+27****1234"`, a masked echo of the *submitted* number, not a DB lookup). The client renders
   the masked string directly — no client-side masking, no POPIA leak risk in the app layer.

10. **"The AI expected-amount is sometimes blank — is that an error or just empty data?"**
    → bill-service: `aiExpectedAmount` is `null` (a valid `200`, not an error) when
    `confidence < 0.85`. The full `GET /bills/:id/ai-estimate` returns `confidence`, `isStale`
    (a stale calc still returns `200` with a "Recalculate" prompt), and `503 ai_unavailable` on
    the 15-second sync timeout. Each outcome maps to a defined screen-inventory fallback, so the
    dev never has to guess whether blank = error.

Each of the above was already satisfied by a present field/code/convention — so no service
contract had to be reopened; the work was to surface them as an explicit resolved checklist at the
top of `conventions.md` so a future reader sees the completeness proof, not just trusts it.

### LEARN (verbatim) — TypeScript API contract patterns

For response shapes you reach for an **`interface`**, not a `type`, as the default: an interface
expresses an object contract, is open to declaration-merging, and produces cleaner compiler/codegen
errors — which is exactly what conventions.md §10 mandates (PascalCase interfaces like
`BillResponse`, `ObjectionCreateRequest`; `…Request` / `…Response` suffixes; camelCase fields). You
fall back to **`type`** only when you need something an interface cannot express — unions,
intersections, mapped or conditional types, or aliasing a primitive — which is why the envelope
itself is the generic `interface ApiResponse<T>` (§2) while a closed string set of error codes would
be a `type` union. The envelope is the spine: `{ data: T | null; error: ApiError | null }` with the
biconditional that exactly one side is non-null, so a single generic `ApiResponse<T>.fromJson` in
Dart unwraps every endpoint and the per-contract interface only describes the `T`. Zod sits on the
*request* edge: each route parses its body with a Zod schema, and on failure the server does not
throw a raw 500 — it maps `ZodError.issues` into the §4 `validation_error` body, where `details.fields`
is `{ <dot-joined path>: <first message> }` (e.g. `"address.city": "Required"`), HTTP `400`,
`error.code = "validation_error"`. That precise shape is the contract the Flutter form-error handler
parses: it iterates `details.fields`, keys onto form controls, and paints inline errors — so the Zod
schema and the Dart form handler are two ends of one agreed shape, not two independent guesses.
camelCase serialisation is enforced at the Node boundary (Prisma/DB columns may be snake_case, but the
serializer emits `accountNumber`, `aiExpectedAmount`, etc.) because §10 forbids snake_case anywhere
except inside `error.code` values — and §12 explains *why this can't be left to vigilance*: a casing
slip (`json['accountNumber']` against a wire `account_number`) returns `null` silently, not an error,
so the defence is codegen, not prose. The Flutter Dio model consumes the typed JSON by being
**generated** (`freezed` + `json_serializable` via `build_runner`) from the contract's TS interface,
with `@JsonKey(name: ...)` declared once wherever a wire key differs; the model class is never
hand-written and `json['key']` is never touched outside generated code, so a contract casing change
regenerates the model with zero hand edits and a drift fails at codegen/CI (definition time) rather
than on a screen (debug time). Two semantic rules generation can't enforce, so the model author still
honours them by hand: money is a **decimal string** parsed with `Decimal.parse` never `double` (§9),
and datetimes are UTC ISO-8601 parsed with `DateTime.parse` then converted to local only in the UI
(§9). Net: given any route in these contracts I can write its `…Request`/`…Response` interface from
the data-model fields, state its Zod schema, and predict its 400 body byte-for-byte — which is the
plan's "done when."

### Per-task verdict

- **THINK** — ✅ done. 10 questions produced, each closed by a cited contract element; resolved
  checklist landed in `conventions.md` `## 0`.
- **LEARN** — ✅ done. Interface-vs-type, Zod→400 `details.fields`, camelCase serialisation, and Dio
  generated-model consumption answered, grounded in conventions.md §2/§4/§10/§12.
- **WRITE** — ✅ satisfied by the completed `plans/api-contracts/` sub-scope (10/10 sub-plans, 8/8
  DoD, 42 routes ≥ 31 baseline, orphan-audit PASS true-zero, all cross-refs verified).
