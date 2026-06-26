# 📋 Objection, Evidence & Draft Models

## Background

⛔ BLOCKED[Gate] — requires plan/00-erd.md WRITE task (ERD complete — FK
directions set).
⛔ BLOCKED[Gate] — requires plan/03-bill.md ENUM task (DisputeCategory enum
defined — Objection references it).

The Objection entity is the primary write target of EasyRates. The `ObjectionStatus`
enum has exactly 4 values from the Figma Tracking & Resolution flow; they must not
be extended without a formal decision. The EVIDENCE & CHALLENGE and SUBMISSION flows
create Objection records with attached EvidenceFiles. The SUBMISSION failure path
creates ObjectionDraft records.

## Description

Write the complete Prisma schema blocks for `Objection`, `EvidenceFile`, and
`ObjectionDraft`. Locks in the exact 4 `ObjectionStatus` enum values from the
Figma flows.

## Purpose

To answer: "should Objection records be soft-deleted (so a user cannot permanently
erase their submission history) — and if so, how does the Flutter objection list
screen know whether to show deleted records?"

## Goal

`easy_rates/system-design/docs/data-model/objection.md` — complete Prisma schema
blocks for `Objection`, `EvidenceFile`, and `ObjectionDraft`; `ObjectionStatus` enum
with exactly 4 values; soft-delete policy decision; `referenceNumber` uniqueness.

## Tasks

- [x] ✅ THINK `/socratic "Should an Objection record ever be deleted from the
  database — and if a ratepayer or municipality administrator tries to delete one,
  what are the legal and audit consequences? If we use soft-delete on Objection,
  how does the Flutter objection list screen handle deleted records — and should
  the API ever return soft-deleted records to the client?"`
  Done when: the soft-delete policy for Objection is decided with a written
  legal/audit rationale; the API behaviour for soft-deleted records is stated.

- [x] ✅ ENUM Lock in the `ObjectionStatus` enum. These 4 values are from the
  Figma Tracking & Resolution flow and must not be changed without a formal design
  decision:
  ```prisma
  enum ObjectionStatus {
    UNDER_REVIEW
    UPHELD
    REJECTED
    MORE_INFO_REQUESTED
  }
  ```
  Done when: enum is written as a Prisma enum block; all 4 values match the
  Figma flow exactly.

- [x] ✅ FIELDS Write the Prisma schema block for `Objection`:
  Fields to consider:
  - `id` (UUID)
  - `referenceNumber` (String unique — human-readable reference, e.g. OBJ-2026-001234)
  - `userId` (FK to User)
  - `billId` (FK to Bill — which bill is being disputed)
  - `accountId` (FK to Account — denormalised for faster list queries?)
  - `disputeCategory` (DisputeCategory enum)
  - `status` (ObjectionStatus enum; default UNDER_REVIEW)
  - `description` (String — ratepayer's written description of the dispute)
  - `aiExpectedAmount` (Decimal? — AI-generated expected amount from the bill service)
  - `deletedAt` (DateTime? — soft-delete field; null means not deleted)
  - `submittedAt` (DateTime — when the objection was formally submitted)
  - `createdAt`, `updatedAt`
  - Relations: `user User`, `bill Bill`, `evidenceFiles EvidenceFile[]`,
    `draft ObjectionDraft?`, `notifications Notification[]`,
    `municipalityResponses MunicipalityResponse[]`
  Decide: is `accountId` denormalised on Objection? Justify.
  Done when: every field has a Prisma type; `deletedAt` for soft-delete included;
  `referenceNumber` is `@unique`; `aiExpectedAmount` is optional.

- [x] ✅ EVIDENCE-FIELDS Write the Prisma schema block for `EvidenceFile`:
  Fields to consider:
  - `id` (UUID)
  - `objectionId` (FK to Objection; onDelete: Cascade or Restrict?)
  - `fileName` (String — original file name from Flutter file_picker)
  - `mimeType` (String — as detected by `file-type` npm, not from Content-Type header)
  - `sizeBytes` (Int — file size in bytes)
  - `storageUrl` (String — Azure Blob Storage URL or signed URL reference)
  - `uploadedAt` (DateTime)
  - `deletedAt` (DateTime? — soft-delete; evidence files should match objection
    soft-delete policy)
  Decide: `onDelete` for `EvidenceFile.objectionId` — Cascade (delete evidence when
  objection is soft/hard deleted) or Restrict (prevent objection deletion if evidence
  exists)?
  Done when: every field has a Prisma type; `mimeType` from `file-type` npm noted;
  `onDelete` stated and justified.

- [x] ✅ DRAFT-FIELDS Write the Prisma schema block for `ObjectionDraft`:
  Fields to consider:
  - `id` (UUID)
  - `userId` (FK to User; onDelete: Cascade)
  - `billId` (FK to Bill — which bill this draft is for)
  - `disputeCategory` (DisputeCategory? — may not be selected yet)
  - `description` (String? — may be incomplete)
  - `aiExpectedAmount` (Decimal? — AI amount fetched for this bill, if any)
  - `savedAt` (DateTime — when draft was last saved)
  - Relation: `user User`, `bill Bill`
  Note: ObjectionDraft is a transient entity — it becomes an Objection on successful
  submission. A user may have at most one draft per bill (or per user?). Decide.
  Done when: all fields present; uniqueness constraint on draft-per-bill or draft-per-user
  stated.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/data-model/objection.md`:
  Full Prisma schema blocks for Objection, EvidenceFile, ObjectionDraft;
  ObjectionStatus enum; soft-delete policy; referenceNumber uniqueness.
  Done when: file exists; all 4 status values documented; soft-delete policy stated.

- [x] ✅ VERIFY Check: exactly 4 values in ObjectionStatus. Confirm `referenceNumber`
  is `@unique` on Objection. Confirm `deletedAt` is DateTime? (nullable) for soft-delete.
  Confirm `aiExpectedAmount` is Decimal? (optional).
  Cross-reference with api/objection-service.md (once written): `maxFileSizeBytes`
  and `acceptedMimeTypes[]` from security.md must appear in the Objection POST contract.
  Done when: all confirmations pass.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the legal/audit soft-delete question forces the
   deletion policy to be grounded in POPIA obligations and audit requirements.
   — custom for schema writing.

## Engagement Instructions

Pass condition: `ObjectionStatus` enum has exactly 4 values matching the Figma flow.
Pass condition: `referenceNumber` is `@unique` on Objection.
Pass condition: `deletedAt` (DateTime?) is present on both Objection and EvidenceFile.
Pass condition: soft-delete policy is documented with a legal/audit rationale.
Pass condition: `aiExpectedAmount` (Decimal?) is present on Objection.
Pass condition: `mimeType` on EvidenceFile notes that it comes from `file-type` npm,
not from the client-supplied Content-Type header.
