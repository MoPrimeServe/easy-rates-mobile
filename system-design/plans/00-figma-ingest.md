# 🗺️ Figma Process-Flow Ingest

## Background
This is the hard gate for the entire system-design scope. Nothing in plans/01–10 may
be started until the screen inventory is written and user-confirmed. All service
boundaries, data models, queue decisions, and API contracts derive from this document —
it is the authoritative specification for what EasyRates does.

## Description
Upload and read the Figma PDF export for all seven EasyRates process flows. Extract
every screen, state, decision point (pink diamond), transition arrow, and label into a
structured inventory table. Annotate each row with the exact Flutter widget data fields
it requires — these feed directly into the API contract schemas in plan/09.

## Purpose
To establish a single, agreed source of truth for what the app does before any backend
shape is decided. Every downstream plan traces to a row in screen-inventory.md. A gap
here is a gap in every plan below it.

## Goal
`easy_rates/system-design/docs/screen-inventory.md` — a complete table with zero
unaccounted screens, states, transitions, or decision branches across all seven Figma
flows.

## Tasks

- [x] ✅ THINK `/socratic "What information must I extract from the Figma flows to make
  every backend decision traceable to a user-facing screen state — and what would I
  regret not capturing now?"`
  Done when: you have a written checklist of extraction targets (screens, states,
  diamonds, transitions, terminal nodes, error states, data fields per screen) before
  opening the PDF.  ✓ stated

- [x] ✅ UPLOAD Upload the Figma PDF export to this session. Confirm all seven flows
  are visible: ONBOARDING | FIND PROPERTY | ACCOUNT & SETTINGS | BILL REVIEW |
  EVIDENCE & CHALLENGE | SUBMISSION | TRACKING & RESOLUTION.
  Done when: all seven flow diagrams are readable and named.  ✓ stated

- [x] ✅ EXTRACT Read the PDF flow by flow. For each: list every screen, every state
  within that screen, every pink diamond (decision point) with its two branches, every
  transition arrow with its label, every terminal/success state, every error state
  (OTP Expired, No Match, Upload Failed, Submission Error, etc.).
  Done when: raw extraction notes cover every visible element; nothing is skipped
  because it "seemed minor." Every item on the `/socratic` extraction checklist from
  the THINK task maps to either a column header or a Notes cell — no checklist item
  is unaccounted for in the table.  ✓ verified (screen-inventory.md, 106 rows, all 7 flows)

- [x] ✅ WRITE Write `easy_rates/system-design/docs/screen-inventory.md`.
  Table columns: Flow | Screen Name | States | User-Facing Data Fields | Triggering
  Event | Outgoing Transitions | Service Owner (TBD) | Notes.
  Rules: every pink diamond → two rows (one per branch); every error state → own row;
  every terminal/success state → own row.
  The "User-Facing Data Fields" column must list exactly what a Flutter widget must
  display or accept as input — this column is the source for request/response schema
  design in plan/09.
  Done when: row count matches the extraction notes; no PDF element is absent from
  the table.  ✓ verified (30 KB, 106 rows, all 7 flows covered)

- [x] ✅ VERIFY Cross-check: read the PDF a second time, ticking off each element
  against the table rows. Count pink diamonds in the PDF vs diamond-branch rows in the
  table — numbers must match. Flag anything ambiguous as a named open question.
  Done when: zero unaccounted elements; all ambiguities documented.  ✓ verified (all 6 checks pass)

- [x] ✅ CONFIRM Present the screen inventory to the user for explicit sign-off.
  Done when: user says the inventory is complete and accurate. This is the gate that
  unblocks plans/01–10.  ✓ verified (all 6 checks pass + user sign-off)

## Recommended skill
▶ `/socratic` ✅ — THINK task; surfaces what to capture before the PDF is opened.
   alt: `/unpack` ✅ — if any Figma notation (swimlane, diamond semantics, connector
   labels) is ambiguous.

## Engagement Instructions

Ground truth from Figma PDF (confirmed uploaded — mobile app flows only;
WhatsApp bot diamonds are out of scope):
- Pink diamonds: **9**
- Required diamond-branch rows: **20** (8 diamonds × 2 branches + Status? × 4 branches)
- Minimum total rows: **55** across 7 flows

Downstream from THINK task: the extraction checklist produced by `/socratic` becomes
the column-header audit list for the WRITE task — every checklist item must map to
a column name or a Notes entry in screen-inventory.md before VERIFY runs.

```bash
# 1. File exists
ls -lh easy_rates/system-design/docs/screen-inventory.md
# Expected: present, size > 2 KB

# 2. All 7 flows represented — each must have ≥ 3 rows
for flow in "ONBOARDING" "FIND PROPERTY" "BILL REVIEW" \
            "EVIDENCE" "SUBMISSION" "TRACKING" "ACCOUNT"; do
  printf "%-22s %s rows\n" "$flow:" \
    "$(grep -c "$flow" easy_rates/system-design/docs/screen-inventory.md)"
done
# Expected: no flow returns 0

# 3. Total data-row count
grep -c "^|[^-]" easy_rates/system-design/docs/screen-inventory.md
# Expected: ≥ 55

# 4. All 9 pink diamonds represented
grep -iE \
  "First time user\?|OTP Valid\?|Account Found\?|Manual Match\?|Charges.*correct\?|\
Sufficient evidence\?|Confirm Submission\?|Submission Successful\?|Status\?" \
  easy_rates/system-design/docs/screen-inventory.md | wc -l
# Expected: ≥ 9

# 5. Error / failure states captured
grep -iE "expired|not found|failed|error|no match|rejected|invalid|insufficient" \
  easy_rates/system-design/docs/screen-inventory.md | wc -l
# Expected: ≥ 6 (OTP expired, OTP invalid, account not found,
#                 no match, submission failed, objection rejected)

# 6. User-facing data fields column populated (not blank / — / TBD)
awk -F'|' 'NR>2 && $5 !~ /^\s*(—|TBD)?\s*$/ {c++} END {print c+0}' \
  easy_rates/system-design/docs/screen-inventory.md
# Expected: ≥ 30
```

Gate: all six checks must pass before CONFIRM runs.
User sign-off: after checks pass, user explicitly states "screen inventory is complete" —
that is the signal unblocking plans/01–10.
