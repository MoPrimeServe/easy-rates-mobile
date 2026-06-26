# 🛡️ OWASP Mobile Top 10 Cross-Check

## Background

⛔ BLOCKED[Gate] — requires plans/00-03 complete (POPIA inventory, JWT model,
rate limits, and upload validation must all be defined before this cross-check
can be meaningful — it verifies the design, not individual components).

The OWASP Mobile Top 10 is a cross-cutting audit. It does not produce new design
decisions — it checks that the decisions in plans/00-03 collectively satisfy a
recognised mobile security standard. Running it before those decisions exist
produces a checklist full of "to be determined" answers, which is useless.

## Description

Cross-check the complete EasyRates security design (plans/00-03 + the parent
scope's security surface) against the OWASP Mobile Security Top 10 (2024 edition
or latest). For each of the 10 items, assign a status: Pass (control already
defined), Mitigate (partial control, residual risk accepted), or Accept (no
control, risk formally accepted with justification). No item may be left blank.

## Purpose

To answer: "which OWASP Mobile Top 10 item is hardest to test in CI — and does
that make it the most likely to be violated undetected in production?"

## Goal

`easy_rates/system-design/docs/security/owasp.md` — all 10 items with
Pass/Mitigate/Accept status, a one-line evidence for Pass items, and a residual
risk statement for Mitigate/Accept items.

## Tasks

- [x] ✅ THINK `/socratic "Which of the OWASP Mobile Top 10 items is hardest to
  test automatically in CI — and does that mean it is the most likely to be violated
  undetected in production? Which item are we most at risk of thinking we've handled
  when we haven't?"`
  Done when: the two highest-risk items (hard to test + high impact) are identified;
  each has a written reason for why it is particularly hard to catch.

- [x] ✅ LEARN `/unpack "OWASP Mobile Security Top 10 (2024 edition) — each item
  title, what it means technically, what it looks like in a Flutter mobile client and
  a Node.js backend, and the canonical control for each item"`
  Done when: you can describe each of the 10 items in one sentence from memory; you
  know which items are Flutter-side (client storage, network communication, code
  quality) vs backend-side (insecure authentication, insufficient logging) vs shared.

- [x] ✅ CROSSCHECK Walk all 10 OWASP Mobile Top 10 items in order. For each:
  1. State the item title and one-sentence description.
  2. Assign status: Pass / Mitigate / Accept.
  3. For Pass: cite the control and the plan that defines it (e.g.
     "M2 Insecure Data Storage → Pass: refresh token in flutter_secure_storage,
     no PII written to disk — see sessions.md").
  4. For Mitigate: describe the partial control and the residual risk explicitly.
  5. For Accept: write the formal risk acceptance statement and the trigger that
     would require a control to be added (e.g. "accepted for pilot; PCI DSS
     scope change would require AV scan on uploads — see upload-validation.md").
  Key items to address:
  M1 — Improper Credential Usage (hardcoded secrets, weak auth)
  M2 — Inadequate Supply Chain Security
  M3 — Insecure Authentication/Authorisation
  M4 — Insufficient Input/Output Validation
  M5 — Insecure Communication
  M6 — Inadequate Privacy Controls (POPIA — this should be Pass if plan/00 is done)
  M7 — Insufficient Binary Protections
  M8 — Security Misconfiguration
  M9 — Insecure Data Storage
  M10 — Insufficient Cryptography
  Done when: all 10 items assigned Pass/Mitigate/Accept; no blank entries; every
  Pass has a cited plan reference.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/security/owasp.md`:
  One table: Item | Title | Status | Evidence/Control | Plan Reference | Residual Risk
  Add a preamble stating the OWASP version referenced and the date of the cross-check.
  Add a note on the two high-risk items identified in the THINK task.
  Done when: 10-row table complete; version referenced; THINK finding documented.

- [x] ✅ VERIFY Count Pass / Mitigate / Accept. If any item is Accept with no
  stated trigger for reconsideration, flag it — a pure Accept with no trigger is a
  security debt that never gets paid.
  Also confirm: every Pass item has a plan reference that actually exists on disk.
  Done when: all Accept items have a reconsideration trigger; all Pass plan
  references resolve to existing files.

## Recommended skill

▶ `/socratic` ✅ — THINK task; identifying the hardest-to-test item forces the
   cross-check to focus attention where automated CI is blind.
   alt: `/unpack` ✅ — OWASP Mobile Top 10 content if the 10 items are not
   already well-known.

## Engagement Instructions

Pass condition: all 10 OWASP Mobile Top 10 items appear in the table with a
status of Pass / Mitigate / Accept — no blank rows.
Pass condition: every Pass entry cites the plan document that provides the control.
Pass condition: every Accept entry has a stated trigger for when the risk would
require a control.
Pass condition: no item has a status of "to be determined" or "pending."
Pass condition: the OWASP version and cross-check date are stated at the top of
owasp.md.
