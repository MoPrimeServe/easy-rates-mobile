# 🔐 POPIA Field Inventory

## Background

⛔ BLOCKED[Gate] — requires parent plan/07-security-design.md LEARN task (POPIA obligations understood).
⛔ BLOCKED[Gate] — requires data-model sub-scope plan/00-erd.md WRITE task (entity list
and fields finalised — this plan walks those fields).

Every other security control in this sub-scope is derived from knowing which fields are
sensitive. A rate limit is pointless if the unprotected field is in a public endpoint.
An audit log is pointless if you haven't identified which fields trigger it. This plan
runs first.

## Description

Walk every field in all 12 Prisma models. Classify each field as PII / Financial /
Operational / Non-sensitive. For every PII and Financial field, name the protection
control. Flag `idNumber` as special personal information under POPIA — it carries
stricter obligations than ordinary PII (name, address, phone number).

## Purpose

To answer: "which field in our database, if exposed without authorisation, would
trigger a POPIA breach notification — and what technical control prevents that
exposure today?"

## Goal

`easy_rates/system-design/docs/security/popia-inventory.md` — complete field
classification table across all 12 models; every PII/Financial field has a named
control; `idNumber` is flagged as special personal information with its stricter
protection control documented.

## Tasks

- [x] ✅ THINK `/socratic "Which field in our 12 Prisma models, if exposed to an
  unauthorised third party, would trigger a POPIA notification obligation — and how
  many users would be affected if that field were leaked? What is the difference
  between a field that embarrasses us and one that creates legal liability?"`
  Done when: the PII fields are ranked by sensitivity and legal risk; `idNumber` is
  identified as special personal information with its stricter obligations named.

- [x] ✅ LEARN `/unpack "POPIA — what constitutes 'personal information' vs 'special
  personal information' under the Act, what a 'responsible party' (the municipality)
  must implement for each category, the breach notification timeline, and what the
  Information Regulator can impose if controls are inadequate"`
  Done when: you can list the POPIA obligations that apply to EasyRates in plain
  English; you know which fields in the data model are 'special personal information'
  and what additional controls they require.

- [x] ✅ WALK Walk every field in the 12 Prisma models in order:
  User | OTPAttempt | Property | Account | Bill | BillLineItem | Objection |
  EvidenceFile | ObjectionDraft | Notification | MunicipalityResponse |
  AIAmountCalculation
  For each field, assign a classification:
  PII (name, idNumber, address, accountNumber, phoneNumber, email) |
  Financial (billing amounts, payment history, arrears, aiExpectedAmount) |
  Operational (status, timestamps, referenceNumber, boolean flags) |
  Non-sensitive (internal UUIDs, model version strings, pagination metadata)
  Done when: every field in every model has a classification; no field is unclassified.

- [x] ✅ CONTROLS For every PII and Financial field, name the protection control:
  `idNumber` — special personal information: encryption at rest + row-level access
  restriction + audit log on every access (stricter than ordinary PII)
  `phoneNumber` — PII: used only for OTP delivery; not returned in general profile
  responses; rate-limited endpoint
  Financial fields (`amount`, `arrears`, `totalAmount`) — Financial: returned only
  to the authenticated account holder; never cached; audit log on bulk access
  For each control: name the mechanism (access restriction, cache exclusion, audit
  log, encryption at rest) and the plan that enforces it (sessions.md,
  rate-limits.md, node-hardening.md).
  Done when: every PII/Financial field has a named control; no field is classified
  sensitive without a corresponding control.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/security/popia-inventory.md`:
  Table format: Model | Field | Classification | Control | Plan reference
  Include a preamble paragraph explaining what POPIA requires for each classification
  category; include a note on `idNumber` as special personal information.
  Done when: all 12 models appear in the table; every PII/Financial field has a
  named control; every Operational and Non-sensitive field has a written reason.

- [x] ✅ VERIFY Spot-checks completed: `refNumber` on Objection → Operational (case
  reference; not person-identifying without account context — see popia-inventory.md);
  `BillLineItem.historicalAverage` and `AIAmountCalculation.estimatedAmount` → Financial
  (consumption comparison, account-specific); `MunicipalityResponse.note` and
  `adjustedAmount` → Operational and Financial respectively.
  Note: plan referenced `rawPayload` on MunicipalityResponse — this field does not exist
  in the finalized data model (model has `note String?` and `adjustedAmount Decimal?`);
  spot-checks done against actual fields. ✓ verified

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "which field creates legal liability" framing forces
   POPIA classification to be grounded in actual risk rather than intuition.
   alt: `/unpack` ✅ — POPIA obligations if the distinction between personal information
   and special personal information is not already clear.

## Engagement Instructions

Pass condition: every field in all 12 Prisma models appears in the inventory table with
a classification.
Pass condition: every PII and Financial field has a named control referencing a specific
security mechanism.
Pass condition: `idNumber` is classified as special personal information with a written
explanation of why it carries stricter obligations than other PII fields.
Pass condition: no field is classified Non-sensitive without a written reason.
Pass condition: every control references the plan document that enforces it.
