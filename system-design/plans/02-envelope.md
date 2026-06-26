# 📊 Back-of-Envelope Capacity Planning

## Background

Every sizing decision downstream — database indexes, Azure tier, Redis memory allocation,
queue worker count, CDN bandwidth — is only as good as the numbers it rests on. This
plan produces those numbers before any technology is chosen. NFR targets (plan/05),
data model sizing (plan/06), and container resource limits (plan/08) all draw from
envelope.md rather than inventing their own figures.

## Description
Estimate the scale EasyRates must serve: Emfuleni ratepayer population, realistic
adoption curve, peak concurrent sessions, database row counts per table, evidence file
storage volume, read/write ratios per service, and an indicative Azure cost range for
pilot and production tiers. Every estimate is documented with its source or assumption
so it can be revised when real data arrives.

## Purpose
To answer: "what is the worst-case day for this system — what event drives peak load —
and what do Emfuleni's own numbers tell us?" Without grounded estimates, every
subsequent plan is built on guesswork dressed as decisions.

## Goal
`easy_rates/system-design/docs/envelope.md` — a single document with pilot and
production columns covering: ratepayer headcount, concurrent session estimate, DB row
counts per table, storage volume, read/write ratios per service, and Azure cost range.
Every number has a source or a labelled assumption. Zero invented figures.

## Tasks

- [x] ✅ THINK `/socratic "What is the worst-case day for this system — what event
  would drive the highest concurrent load — and what does Emfuleni's IDP or public
  data tell us about the actual numbers we should plan for?"`
  ✓ verified — envelope.md §Peak-Load Scenario (WhatsApp-driven social spike narrative);
  socratic learning capture in learning/emfuleni-load-design-and-ratepayer-data-2026-06-19/

- [x] ✅ LEARN `/unpack "Emfuleni Local Municipality — ratepayer population, household
  count, billing cycle, and collection rate from the 2026/27 IDP or available public
  municipal data"`
  ✓ verified — envelope.md "Consumer account base → 250,000" (Census 2022 derivation);
  unpack learning capture in learning/emfuleni-load-design-and-ratepayer-data-2026-06-19/

- [x] ✅ ESTIMATE Produce the back-of-envelope numbers.
  ✓ verified — envelope.md §Estimates: 16-row table covering all items a–h,
  pilot and production columns, inline assumptions on every row; no blank cells.
  Load anchor propagated to plan/05 and plan/08 as required.

- [x] ✅ COST Open the Azure Pricing Calculator. Size two configurations.
  ✓ verified — envelope.md §Azure Cost Estimates: pilot ~$34/mo East US (~$39 SA North);
  production ~$497/mo East US (~$572 SA North); 4 line items each with tier and USD figure.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/envelope.md`.
  ✓ verified — file exists (12 KB); all 7 gate checks pass (36 pilot/production mentions,
  0 TBD cells, 19 Azure service references, 12 peak/concurrent lines, 18 source labels).

- [x] ✅ VERIFY Sanity-check each order of magnitude.
  ✓ verified — envelope.md §Verification record (2026-06-20): all estimates defended
  in one sentence; no number off by 10×; sensitivity table documents adoption and spike-rate
  uncertainty; external review flagged for practitioner with SA municipal data experience.

## Recommended skill
▶ `/socratic` ✅ — THINK task; the peak-load scenario framing is the key question that
   makes all downstream sizing decisions defensible.
   alt: `/unpack` ✅ — Emfuleni IDP data or Azure pricing tiers if either is unfamiliar.

## Engagement Instructions

```bash
# 1. File exists
ls -lh easy_rates/system-design/docs/envelope.md
# Expected: present, size > 2 KB

# 2. Both pilot and production columns present
grep -iE "pilot|production" easy_rates/system-design/docs/envelope.md | wc -l
# Expected: ≥ 10 (heading row + one mention per estimate row)

# 3. No blank cells or TBD values remain
grep -iE "\|\s*TBD\s*\||\|\s*\?" easy_rates/system-design/docs/envelope.md
# Expected: 0 results

# 4. Azure cost table present with at least 4 line items
grep -iE "azure sql|app service|redis|blob storage" \
  easy_rates/system-design/docs/envelope.md | wc -l
# Expected: ≥ 4 (one per Azure service tier row)

# 5. Peak-load scenario narrative present
grep -iE "peak|concurrent|worst.case|billing.cycle|deadline|last business" \
  easy_rates/system-design/docs/envelope.md | wc -l
# Expected: ≥ 3 lines

# 6. Every number has a source or assumption label
grep -iE "source:|assumption:|estimate:|~[0-9]|≈[0-9]|\([Ss]ource\)" \
  easy_rates/system-design/docs/envelope.md | wc -l
# Expected: ≥ 8 (one per major numeric row a–h)

# 7. Concurrent-session figure is explicitly stated
grep -iE "concurrent session|peak session|simultaneous" \
  easy_rates/system-design/docs/envelope.md
# Expected: ≥ 1 line with a specific number (not a range like "TBD–TBD")
```

Gate: all 7 checks must pass before plans/05, 06, and 08 may start.
The concurrent-session figure from check 7 must appear verbatim in both
plan/05 (NFR latency targets) and plan/08 (container resource limits) as
their load anchor — neither plan may derive its own session estimate.
