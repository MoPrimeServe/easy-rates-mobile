# 🔒 Security Design

## Background
⛔ BLOCKED[Gate] — requires plans/01-service-boundaries.md VERIFY task (service map
finalised).
⛔ BLOCKED[Gate] — requires plans/06-data-model.md VERIFY task (data model finalised —
POPIA field inventory is a walk of the model field tables).

EasyRates handles personal municipal account data: account numbers, property addresses,
billing amounts, identity numbers, and submitted objections with supporting documents.
South Africa's Protection of Personal Information Act (POPIA) imposes legal obligations
on collection, storage, access, and breach notification. A security failure here is not
a technical incident — it is a legal and reputational event for the municipality. This
plan is non-optional.

## Description
Identify every field that constitutes personal information under POPIA. Define the JWT
security model (algorithm, TTL, storage, rotation). Design rate limits per endpoint
category using Node.js middleware. Specify file upload validation (magic-byte MIME check
via `file-type` npm package, size limit, AV scan decision). Cross-check the design
against the OWASP Mobile Top 10. Run the Node.js production hardening checklist.

## Purpose
To answer: "which field in our database, if leaked or accessed without authorisation,
would trigger a POPIA notification obligation — and what technical control prevents
that access today?" Every security control defined here is a non-optional design
constraint on the API contracts and the data model.

## Goal
`easy_rates/system-design/docs/security.md` — POPIA field inventory, JWT security
model, rate-limit table, file upload validation rules, OWASP Mobile Top 10 cross-check,
and Node.js production hardening checklist results.

## Tasks

- [x] ✅ THINK `/socratic "Which field in our database, if leaked or accessed without
  authorisation, would trigger a POPIA breach notification obligation — and what is
  the technical control that prevents that access today? If that control fails, what
  is the next line of defence?"`
  Done when: every POPIA-sensitive field is named; each has a primary control and
  a secondary control; any field with no control is flagged as an open gap.
  Downstream: the named POPIA-sensitive fields and their primary/secondary controls
  become the opening "Field Risk Register" section of security.md — write it before
  POPIA-INVENTORY walks the full model, so the highest-risk fields are already
  flagged and the inventory confirms coverage rather than discovering risk mid-walk.

- [x] ✅ LEARN `/unpack "POPIA — what constitutes 'personal information' and 'special
  personal information' under the Act, what a 'responsible party' (the municipality)
  must implement, what the breach notification timeline is, and what the Information
  Regulator can do if controls are inadequate"`
  Done when: you can list the POPIA obligations relevant to EasyRates in plain
  English, and you know which fields in the data model are "special personal
  information" (identity numbers, financial data) with stricter obligations.

- [x] ✅ POPIA-INVENTORY Walk every field in data-model.md. Classify each as:
  PII (name, ID number, address, account number, phone number) |
  Financial (billing amounts, payment history, arrears) |
  Operational (objection status, submission timestamps) |
  Non-sensitive (internal UUIDs, boolean flags, created_at).
  For every PII and Financial field: name the protection control (encryption at rest,
  access log, row-level security, or restricted endpoint).
  Done when: every model field is classified; every PII/Financial field has a named
  control; no field is classified "non-sensitive" without a reason.

- [x] ✅ JWT Define the full JWT security model:
  a. Algorithm: HS256 (symmetric, simpler) vs RS256 (asymmetric, supports key
     rotation without shared secret). Choose one and justify.
  b. Access token: TTL (minutes), stored in Flutter in-memory only (never written
     to disk — justify why in-memory is the right choice for mobile).
  c. Refresh token: TTL (days), stored in Flutter `flutter_secure_storage`, rotation
     policy (rotate on every use? on expiry only?).
  d. Token revocation: is a Redis blacklist needed, or does short access token TTL
     + refresh token rotation make blacklisting unnecessary?
  e. Key rotation: how is the signing key rotated without invalidating all active
     sessions simultaneously?
  Done when: all five sub-decisions are made and documented; Flutter storage
  location explicitly stated for both token types.
  Downstream: the algorithm, access token TTL, and refresh token TTL chosen here are
  copied verbatim into backend plans/03 (auth-service implementation) as the JWT
  configuration constants. No auth-service implementation may choose its own algorithm
  or TTL; if the values change here, the backend plan is updated first.

- [x] ✅ RATE-LIMITS Define rate limits per endpoint category using Node.js middleware
  (`express-rate-limit` or equivalent). Justify the chosen library.
  Auth endpoints (login, register): e.g. 5 requests / minute / IP
  OTP endpoints (send, resend): e.g. 3 requests / 15 minutes / phone number
  Read endpoints (property lookup, bill fetch): e.g. 60 requests / minute / user
  Write endpoints (objection submit): e.g. 10 requests / hour / user
  For each: the scope (IP, user, phone), the window, and the middleware configuration
  that enforces it.
  Done when: rate-limit table complete; enforcement middleware specified for each
  category.
  Downstream: the rate-limit table (scope, window, limit per endpoint category) is
  copied into plan/09 (API contracts) as a non-functional constraint on each endpoint
  spec. Any endpoint in api/*.md that has no rate-limit entry is a gap that must be
  resolved before API contracts are locked.

- [x] ✅ FILE-UPLOAD Define upload validation rules for the Evidence & Challenge flow:
  a. Accepted MIME types: PDF, JPG, PNG (no executables, no ZIP, no HTML).
  b. Max file size: derive from envelope.md storage estimate and Azure Blob limits.
  c. MIME validation approach: server-side magic-byte check using the `file-type`
     npm package (reads the file buffer header), not the HTTP Content-Type header
     (trivially spoofed) and not the file extension (also spoofed). Document the
     implementation approach.
  d. Antivirus: is ClamAV (open-source, self-hosted) or Azure Defender for Storage
     (managed) required at pilot stage? Document the decision and cost.
  Done when: all four rules documented; magic-byte check library and implementation
  approach specified.

- [x] ✅ OWASP Cross-check the planned design against the OWASP Mobile Top 10
  (2023 edition). For each of the ten items: Pass, Mitigate (with control named),
  or Accept (with explicit rationale). No item left blank.
  Key items to examine carefully for EasyRates:
  M1 Improper Credential Usage — JWT storage strategy
  M2 Inadequate Supply Chain Security — third-party packages in Node.js and Flutter
  M5 Inadequate Privacy Controls — POPIA field handling
  M8 Security Misconfiguration — Node.js environment configuration for production
  Done when: all 10 items addressed with Pass/Mitigate/Accept and a one-line note.

- [x] ✅ NODE-HARDENING Validate the Node.js production environment configuration
  against the hardening checklist before this plan closes.
  Key checks: `helmet.js` middleware installed and configured; HTTPS enforced (no
  plain HTTP in production); environment variables validated at startup with `zod`
  or `envalid` (crash-fast on missing secrets); no secrets in code or committed
  files; CORS policy locked to known origins; `Content-Security-Policy` header set.
  Done when: every checklist item is Pass or documented Accept/Mitigate; no item
  left blank.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/security.md` covering all sections
  above.  → decomposed: see `plans/security/MASTER_PLAN.md`
  Done when: all six sub-documents in plans/security/ are complete and security.md
  links to them.

- [x] ✅ VERIFY Blast-radius test: if an attacker obtains a valid access token for
  user A, what can they access?
  Expected answer: only user A's own accounts, properties, bills, and objections.
  No other user's data. No admin endpoints. No ability to list all users.
  Document the Prisma query pattern that enforces user-scoping (e.g.
  `prisma.objection.findMany({ where: { userId: req.user.id } })`) in every endpoint.
  Done when: blast-radius is confirmed user-scoped; the queryset pattern is
  documented; any endpoint that could return cross-user data is flagged.

## Recommended skill
▶ `/socratic` ✅ — THINK task; the breach-notification framing immediately surfaces
   the highest-risk fields and forces controls to be named, not assumed.
   alt: `/unpack` ✅ — POPIA obligations or JWT rotation patterns if either is
   not already well understood.

## Engagement Instructions

```bash
# 1. File exists
ls -lh easy_rates/system-design/docs/security.md
# Expected: present, size > 3 KB

# 2. POPIA inventory covers key PII/Financial fields
for field in "identity.*number\|ID number" "account.*number\|accountNumber" \
             "address\|erf" "billing.*amount\|arrears\|amount.*due" \
             "phone\|mobile.*number"; do
  printf "%-45s %s lines\n" "$field:" \
    "$(grep -icE "$field" easy_rates/system-design/docs/security.md)"
done
# Expected: each ≥ 1 (field present in POPIA inventory)

# 3. JWT model: all 5 sub-decisions documented
for item in "HS256\|RS256\|algorithm" \
            "access.*TTL\|access.*token.*[0-9].*min" \
            "refresh.*TTL\|refresh.*token.*[0-9].*day" \
            "flutter_secure_storage\|in.memory\|never.*disk" \
            "revoc\|blacklist\|rotation"; do
  printf "%-45s %s lines\n" "$item:" \
    "$(grep -icE "$item" easy_rates/system-design/docs/security.md)"
done
# Expected: each ≥ 1

# 4. Rate-limit table covers all 4 endpoint categories
for cat in "login\|register\|auth" "OTP\|otp.*send\|otp.*resend" \
           "property\|bill.*fetch\|read" "objection.*submit\|write"; do
  printf "%-40s %s lines\n" "$cat:" \
    "$(grep -icE "$cat" easy_rates/system-design/docs/security.md)"
done
# Expected: each ≥ 1

# 5. Magic-byte MIME validation (file-type npm) specified
grep -iE "file.type|magic.byte|buffer.*header|mime.*validation" \
  easy_rates/system-design/docs/security.md | wc -l
# Expected: ≥ 2 (library name + implementation approach)

# 6. OWASP Mobile Top 10 — all 10 items addressed
for item in "M1" "M2" "M3" "M4" "M5" "M6" "M7" "M8" "M9" "M10"; do
  printf "%-6s %s\n" "$item:" \
    "$(grep -c "$item" easy_rates/system-design/docs/security.md)"
done
# Expected: each ≥ 1 (Pass/Mitigate/Accept entry per item)

# 7. Node.js hardening checklist items present
for check in "helmet" "HTTPS\|https" "CORS\|cors" \
             "zod\|envalid\|env.*valid" "Content-Security-Policy\|CSP"; do
  printf "%-35s %s lines\n" "$check:" \
    "$(grep -icE "$check" easy_rates/system-design/docs/security.md)"
done
# Expected: each ≥ 1

# 8. Blast-radius: user-scoping query pattern documented
grep -iE "userId.*req\.user|where.*userId|user.scoped\|blast.radius" \
  easy_rates/system-design/docs/security.md | wc -l
# Expected: ≥ 1 (Prisma queryset pattern shown)
```

Gate: all 8 checks must pass before plan/09 (API contracts) and backend plans/03
(auth-service) may start.
Checks 3 and 4 feed downstream plans by reference — if any value changes in
security.md after those plans have started, raise it as a scope-change to the
scrum_master, not a silent edit.
