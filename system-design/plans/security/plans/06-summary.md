# 📄 Security Summary Document

## Background

⛔ BLOCKED[Gate] — requires plans/00-05 complete (all six security domain documents
must exist on disk before the summary can link and distil them).

The summary document is the artifact that plan/07-security-design.md in the parent
scope links to — it is what the architect reads to confirm the security design is
complete. It does not replace the six domain documents; it distils the key decisions
from each and provides a single navigation entry point.

## Description

Write the top-level `docs/security.md` that links all six security sub-documents,
summarises the key decision in each, and provides a one-paragraph security posture
statement for EasyRates. This document is the input artifact for ADR-001.

## Purpose

To produce a single document that answers: "is the EasyRates security design
complete — and what are the five most important things a new team member must
know about it?"

## Goal

`easy_rates/system-design/docs/security.md` — navigation entry point for the
complete security design; one section per sub-document; five-point orientation
summary for new team members; no new decisions introduced here.

## Tasks

- [x] ✅ WRITE Write `easy_rates/system-design/docs/security.md`:

  Structure:
  # EasyRates Security Design

  ## Posture summary
  One paragraph: Flutter mobile client + Node.js backend. POPIA obligations for
  all 12 entities. JWT access/refresh model. Four rate-limit categories.
  Magic-byte file validation. OWASP Mobile Top 10 cross-checked. Node.js
  production hardening applied. State the overall risk posture in one sentence.

  ## Sub-documents
  - [POPIA Field Inventory](docs/security/popia-inventory.md) — [one-line key
    finding: which field carries the strictest obligation and what the control is]
  - [JWT Security Model](docs/security/sessions.md) — [one-line key decision:
    algorithm, TTL values, storage, rotation policy]
  - [Rate Limits](docs/security/rate-limits.md) — [one-line key decision:
    four categories, middleware choice, Redis store trigger]
  - [Upload Validation](docs/security/upload-validation.md) — [one-line key
    decision: accepted types, max size, magic-byte check, AV scan decision]
  - [OWASP Mobile Top 10](docs/security/owasp.md) — [one-line result:
    Pass/Mitigate/Accept counts; any item left as Accept with a trigger]
  - [Node.js Hardening](docs/security/node-hardening.md) — [one-line key
    decision: helmet.js enabled, startup validation, CORS config]

  ## Five things a new team member must know
  1. [Most important security decision — e.g. JWT storage model]
  2. [Second most important — e.g. POPIA field controls for idNumber]
  3. [Third — e.g. magic-byte upload validation]
  4. [Fourth — e.g. rate-limit scope (IP vs userId vs phone)]
  5. [Fifth — e.g. the one OWASP Accept item with its trigger]

  Done when: all six sub-documents are linked with one-line key findings;
  posture summary paragraph is written; five-point orientation section is
  present and specific (not generic).

- [x] ✅ VERIFY Check that the "five things a new team member must know" section
  would actually orient a new developer — not a list of feature names, but actual
  actionable facts (e.g. "the refresh token is stored in flutter_secure_storage,
  not in the access token payload — do not put user data in the access token").
  Also confirm: every sub-document linked in this summary exists on disk at the
  path stated.
  Done when: five-point section is specific and actionable; all six links resolve.

## Recommended skill

— custom; no skill fits (this is assembly and synthesis, not research or analysis).

## Engagement Instructions

Pass condition: all six sub-document links present and resolve to existing files.
Pass condition: each sub-document entry has a one-line key finding that is specific
to EasyRates (not a generic statement like "authentication is implemented").
Pass condition: posture summary paragraph states the overall risk posture in one
sentence.
Pass condition: five-point orientation section contains actionable facts that
a developer would act on — not topic headings.
Pass condition: no new security decisions are introduced in this summary document;
every claim is sourced from one of the six sub-documents.
