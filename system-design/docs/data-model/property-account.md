# EasyRates — Property, Account & Municipality Models

**Service ownership:** property-service (Property) · account-service (Account) · shared/seed (Municipality)  
**Patches applied:** DECISION-A (deletedAt on Account) · DECISION-C (municipalityId on Property, Account) · DECISION-D (cuid PKs)

---

## Enum

```prisma
enum AccountStatus {
  ACTIVE
  INACTIVE  // account closed or suspended by municipality
  ARCHIVED  // soft-deleted; follows User.deletedAt in the same transaction
}
```

---

## Model: Municipality

```prisma
model Municipality {
  id   String @id @default(cuid())
  name String @unique
  code String @unique

  properties Property[]
  accounts   Account[]
  bills      Bill[]
  objections Objection[]
}
```

### Field table

| Field | Prisma type | Optional? | @unique | @@index | @default | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| id | String | No | — | — | cuid() | |
| name | String | No | Yes | — | — | "Emfuleni Local Municipality" |
| code | String | No | Yes | — | — | "EMFULENI" |

Seed record (Phase 1 only): `{ name: "Emfuleni Local Municipality", code: "EMFULENI" }`.

In Phase 1, all writes hard-code `municipalityId` to this seed record's id. No query filtering by `municipalityId` in service handlers — the value is always Emfuleni. See DECISION-C for the Phase 2 upgrade path.

`onDelete: Restrict` on all FK children — a Municipality row cannot be deleted while any Property, Account, Bill, or Objection references it.

---

## Model: Property

```prisma
model Property {
  id             String @id @default(cuid())
  municipalityId String
  accountNumber  String @unique
  address        String
  erfNumber      String?
  ownerName      String?
  holderIdNumberHashes String[] // HMAC-SHA256(pepper, holder SA ID) per holder; plaintext not stored — ADR-003
  city           String @default("Emfuleni")
  metadata       Json?  // raw fields from the municipality billing system sync

  municipality Municipality @relation(fields: [municipalityId], references: [id], onDelete: Restrict)

  @@index([erfNumber])
}
```

### Field table

| Field | Prisma type | Optional? | @unique | @@index | @default | Index justification |
| --- | --- | --- | --- | --- | --- | --- |
| id | String | No | — | — | cuid() | |
| municipalityId | String | No | — | — | — | DECISION-C FK; Phase 1 always Emfuleni |
| accountNumber | String | No | Yes | — | — | Lookup key; @unique creates the index |
| address | String | No | — | — | — | |
| erfNumber | String | Yes | — | Yes | — | Property search: `WHERE erfNumber = ?` on 30k rows |
| ownerName | String | Yes | — | — | — | |
| holderIdNumberHashes | String[] | No | — | — | [] | ADR-003: hashed holder SA IDs from the municipal sync; feeds the property identity gate. Plaintext holder IDs (in the raw export / `metadata`) are not persisted as a typed column |
| city | String | No | — | — | "Emfuleni" | |
| metadata | Json | Yes | — | — | — | Sync fields not mapped to typed columns |

**`@unique` on accountNumber** — Property is the authority record for an account number. `Account.accountNumber` and `Bill.accountNumber` are soft references to this value, not FK columns. This unique constraint is the closest enforcement mechanism. See below.

**`@@index([erfNumber])`** — The PROPERTY SEARCH flow queries by ERF number: `WHERE erfNumber = ?`. Projected 30,000 rows — crosses the 10k threshold; index is justified. Not a `@unique` because the same ERF can have multiple service accounts (one property, three accounts: water, electricity, rates).

### Soft-reference note

Property is **never the FK parent** of Account or Bill in the database schema. The municipality's billing system issues account numbers as stable identifiers; those numbers appear in Property, Account, and Bill records. There is no DB-level FK enforcing the match. A foreign key here would break on municipality data resync — resync may delete and re-insert Property rows, and a FK from Account or Bill would cause constraint violations.

Property is **hard-deleted on resync**. DECISION-A does not apply. The municipality's billing system is the authority; EasyRates mirrors it.

---

## Model: Account

```prisma
model Account {
  id             String        @id @default(cuid())
  userId         String
  municipalityId String
  accountNumber  String        @unique
  status         AccountStatus @default(ACTIVE)
  deletedAt      DateTime?     // DECISION-A: soft-delete; follows User.deletedAt
  createdAt      DateTime      @default(now())

  user         User         @relation(fields: [userId], references: [id], onDelete: Cascade)
  municipality Municipality @relation(fields: [municipalityId], references: [id], onDelete: Restrict)

  @@index([userId])
}
```

### Field table

| Field | Prisma type | Optional? | @unique | @@index | @default | Index justification |
| --- | --- | --- | --- | --- | --- | --- |
| id | String | No | — | — | cuid() | |
| userId | String | No | — | Yes | — | `@@index([userId])` — GET /account/me; VERIFY confirmed seq scan at 90k rows without it |
| municipalityId | String | No | — | — | — | DECISION-C FK |
| accountNumber | String | No | Yes | — | — | @unique creates the index; hot query key |
| status | AccountStatus | No | — | — | ACTIVE | |
| deletedAt | DateTime | Yes | — | — | — | DECISION-A soft-delete marker |
| createdAt | DateTime | No | — | — | now() | |

**`@@index([userId])`** — the `GET /account/me` endpoint issues `findMany({ where: { userId, deletedAt: null } })`. Without this index, every home screen load scans all 90,000 Account rows. VERIFY (2026-06-20) confirmed 720 buffer hits per query at production scale; at 5,000 peak concurrent sessions this saturates S2 DTU. The previous reasoning ("accountNumber @unique makes a userId index unnecessary") was incorrect — the two fields serve independent lookup paths.

### Lifecycle

Account is soft-deleted (not hard-deleted) because:
1. `Bill.accountNumber` is a soft reference to `Account.accountNumber`. Historical bills must remain queryable by account number even after account closure.
2. If User is soft-deleted, the soft-delete middleware cascades to all linked Accounts in the same transaction.

`onDelete: Cascade` on `Account.userId` — if User is hard-deleted (not applicable in production given DECISION-A, but possible in test environments), all linked Accounts cascade-delete.
