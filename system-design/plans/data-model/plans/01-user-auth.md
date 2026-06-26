# 👤 User & OTP Models

## Background

⛔ BLOCKED[Gate] — requires plan/00-erd.md WRITE task (ERD complete — FK directions
and `onDelete` policies for User and OTPAttempt are set before field detail is added).

User and OTPAttempt are the entry point for every Figma flow. The `idNumber` field on
User is special personal information under POPIA — it carries stricter obligations than
`phoneNumber` or `email`. This plan must cross-reference the POPIA inventory
(`docs/security/popia-inventory.md`) for the `idNumber` protection control.

## Description

Write the complete Prisma schema blocks for the `User` and `OTPAttempt` models.
Includes: all fields with types, optional markers, default values; indexes on
`phoneNumber` and `email`; POPIA note on `idNumber`; FK from `OTPAttempt` to `User`.

## Purpose

To answer: "`idNumber` is special personal information under POPIA — what does that
mean at the Prisma field level, and how does the schema enforce that protection?"

## Goal

`easy_rates/system-design/docs/data-model/user-auth.md` — complete Prisma schema
blocks for `User` and `OTPAttempt`; `idNumber` POPIA cross-reference note; index
justifications; `onDelete` policy for `OTPAttempt.userId`.

## Tasks

- [x] ✅ THINK `/socratic "What happens to an OTPAttempt record if the User it
  belongs to is deleted — should OTPAttempt cascade-delete or be retained? And
  what about idNumber: if it is stored as plaintext in the database, what is the
  worst-case outcome of a database breach — and does the schema need to note an
  encryption requirement?"`
  Done when: the `onDelete` policy for `OTPAttempt.userId` is decided with written
  rationale; the `idNumber` storage decision (plaintext vs encrypted at rest) is
  decided with written rationale.

- [x] ✅ FIELDS Write the Prisma schema block for `User`:
  ```prisma
  model User {
    id          String      @id @default(uuid())
    phoneNumber String      @unique
    email       String?     @unique
    fullName    String
    idNumber    String?     // special personal information — POPIA: see popia-inventory.md
    createdAt   DateTime    @default(now())
    updatedAt   DateTime    @updatedAt
    // relations
    otpAttempts OTPAttempt[]
    properties  Property[]  // via Account? or direct?
    objections  Objection[]
    notifications Notification[]
    @@index([phoneNumber])
    @@index([email])
  }
  ```
  Notes for discussion:
  - Is `idNumber` nullable (user may not supply it)?
  - Does `idNumber` need `@unique` (one account per ID) or is it only
    used for lookup/verification?
  - `properties` relation: does User own Properties directly, or only via Account?
    Clarify the join path.
  Write the definitive schema block with these decisions made.
  Done when: every field has a Prisma type, null policy, and default where applicable.

- [x] ✅ OTP-FIELDS Write the Prisma schema block for `OTPAttempt`:
  ```prisma
  model OTPAttempt {
    id          String   @id @default(uuid())
    userId      String
    code        String   // hashed? or plaintext?
    phoneNumber String   // denormalised for rate-limit queries?
    expiresAt   DateTime
    verified    Boolean  @default(false)
    createdAt   DateTime @default(now())
    user        User     @relation(fields: [userId], references: [id], onDelete: Cascade)
    @@index([userId])
    @@index([phoneNumber])
    @@index([expiresAt])
  }
  ```
  Notes for discussion:
  - Is `code` stored hashed or plaintext? (Hashing is safer; look up by hash on verify.)
  - Is `phoneNumber` denormalised onto OTPAttempt for rate-limit queries, or looked
    up via the User join?
  - Is `expiresAt` indexed for cleanup queries (delete expired OTPAttempts)?
  Write the definitive schema block with these decisions made.
  Done when: every field has a Prisma type; `onDelete` is set; decisions are documented.

- [x] ✅ POPIA-NOTE Add a POPIA cross-reference note to the `idNumber` field comment
  and to the docs/data-model/user-auth.md document:
  "idNumber is South African national identity number — classified as special personal
  information under POPIA s1. Controls: see docs/security/popia-inventory.md.
  If stored, must be encrypted at rest and accessed only under explicit user consent.
  Do not return in general profile API responses."
  Done when: POPIA note is in the schema block comment and in the document prose.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/data-model/user-auth.md`:
  Full Prisma schema blocks for User and OTPAttempt; index justification table;
  POPIA cross-reference note; `onDelete` decision for OTPAttempt.userId.
  Done when: file exists; both schema blocks are complete; POPIA note is present.

- [x] ✅ VERIFY Cross-reference with docs/security/popia-inventory.md: confirm
  `idNumber` classification and control in the inventory matches the note here.
  Cross-reference with api/auth-service.md (once written): confirm `idNumber`
  is not returned in any auth API response without explicit user-consent context.
  Done when: POPIA inventory and user-auth.md are consistent; `idNumber` is not
  in any response schema.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the cascade-delete + `idNumber` encryption decision
   forces the storage policy to be grounded in POPIA obligations.
   — custom for schema writing; no skill produces Prisma schema blocks directly.

## Engagement Instructions

Pass condition: User schema block has all fields with types and null policies.
Pass condition: `idNumber` has a POPIA cross-reference comment in the schema block.
Pass condition: OTPAttempt schema block has `onDelete` specified and justified.
Pass condition: `phoneNumber` and `email` are indexed on User.
Pass condition: OTP code storage decision (hashed vs plaintext) is documented.
Pass condition: POPIA note in the document prose references popia-inventory.md.
