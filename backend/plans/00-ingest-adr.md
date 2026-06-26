# 🗂️ Figma + ADR Ingest — Gap Report

## Background
This is the hard gate for the entire backend scope. No plan from 01 onwards may
start until this plan closes with gap-report.md confirmed empty. The Figma PDF
has already been uploaded to the current session (Process Flows.pdf — covers all
seven EasyRates flows; this scope uses ONBOARDING and FIND PROPERTY).

## Description
Read the Figma process flows and ADR-001 side by side. Map every screen transition
in the two in-scope flows to a specific API route. Map every API route in the
system-design contracts to a specific screen transition. Write any unmatched item
to gap-report.md. Resolve every gap before proceeding.

## Purpose
To prove that the API surface designed in system-design exactly covers the Figma
flows this backend must implement — and that no Figma screen transition is
unaccounted for. A gap here is a missing endpoint or a dead route at integration
time.

## Goal
`easy_rates/backend/docs/gap-report.md` — confirmed empty (zero unmatched
transitions or routes) and user-confirmed before plan/01 starts.

## Tasks

- [ ] ⚠️ T0  Confirm the uploaded Figma PDF covers the two in-scope flows:
  ONBOARDING (App Launch → Home Dashboard) and FIND PROPERTY (Enter Account
  Number → Property Details / No Match). Note any discrepancy with
  `easy_rates/system-design/docs/screen-inventory.md`.
  Done when: all ONBOARDING and FIND PROPERTY screens, decision points (pink
  diamonds), and transition labels are confirmed present in the PDF.

- [ ] ⚠️ T1  Read ADR-001 (`easy_rates/system-design/docs/ADR-001-backend-shape.md`)
  and all API contract files under `easy_rates/system-design/api/`. List every
  HTTP route (verb + path) defined in those contracts.
  Done when: a written route list exists — no route is missing from the tally.

- [ ] ⚠️ T2  Cross-check A → B: for every Figma transition in ONBOARDING and FIND
  PROPERTY, confirm a matching API route exists in the contracts.
  Cross-check B → A: for every API route in the contracts, confirm a matching
  Figma transition exists in the two in-scope flows.
  Write every unmatched item (either direction) to
  `easy_rates/backend/docs/gap-report.md` with: direction (A→B or B→A), the
  Figma label or route, and a one-line note on the gap.
  Done when: every transition and every route has been checked; gap-report.md
  reflects the complete diff.

- [ ] ⚠️ T3  If gap-report.md is non-empty: surface each gap to the user; block
  plan/01 from starting; resolve gaps by either adding a missing route to the
  system-design contracts or confirming a Figma transition is out of scope.
  Done when: every gap is either resolved or explicitly marked out-of-scope
  with a reason.

- [ ] ⚠️ T4  Confirm gap-report.md is empty. Get explicit user sign-off.
  Done when: user confirms the file is empty and plan/01 is unblocked.

## Recommended skill
— custom; no skill fits (cross-check is project-specific; requires both PDF and
contract files in context simultaneously).

## Engagement Instructions

```bash
# 1. gap-report.md exists
ls -lh easy_rates/backend/docs/gap-report.md
# Expected: file present (may be 0 KB if empty)

# 2. Report is truly empty — zero unmatched items
GAPS=$(grep -cvE "^\s*$|^#" easy_rates/backend/docs/gap-report.md 2>/dev/null || echo 0)
echo "Unmatched items in gap-report.md: $GAPS"
# Expected: 0

# 3. All ONBOARDING and FIND PROPERTY Figma transitions accounted for
grep -iE "ONBOARDING|FIND PROPERTY" \
  easy_rates/system-design/docs/screen-inventory.md | wc -l
# Expected: ≥ 15 (transitions across both flows)

# 4. All api/*.md routes tallied — count must match gap-report baseline
ROUTE_COUNT=$(grep -cE "^(GET|POST|PUT|PATCH|DELETE) /api" \
  easy_rates/system-design/api/*.md 2>/dev/null || echo 0)
echo "Total API routes defined: $ROUTE_COUNT"
# Expected: ≥ 31 (per gap-report.md baseline from system-design scope)

# 5. Pink diamonds in ONBOARDING and FIND PROPERTY confirmed covered
# ONBOARDING: First time user? / OTP Valid? (2 diamonds × 2 branches = 4 rows min)
# FIND PROPERTY: Account Found? / Manual Match? (2 diamonds × 2 branches = 4 rows min)
for diamond in "First time user" "OTP Valid" "Account Found" "Manual Match"; do
  printf "%-20s %s rows\n" "$diamond:" \
    "$(grep -ic "$diamond" easy_rates/system-design/docs/screen-inventory.md)"
done
# Expected: each ≥ 1

# 6. User sign-off recorded (manual gate — confirm explicitly)
echo "Gap-report confirmed empty. Awaiting user sign-off to unblock plan/01."
```

Gate: checks 1–2 must show 0 unmatched items AND the user must explicitly confirm
before plan/01 starts. Check 2 is the hard gate — a non-zero count means a
missing endpoint or a dead route will surface at integration time in plan/07.
