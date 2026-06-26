# EasyRates — Schema Design Decisions

**Status:** Committed  
**Date:** 2026-06-20  
**Author:** System Design session  
**Downstream:** plan/07 (security) · plan/08 (container topology) · plan/09 (API contracts)

No decision below may be re-opened without a written migration cost estimate and a named
approver. "We'll decide later" is not an acceptable state for any of the four questions.

---

## DECISION-A: Soft-Delete Policy

### Decision

Use `deletedAt DateTime?` (soft-delete) on five models. Hard delete on the remaining
nine. No model uses a boolean `isDeleted` flag — the check is always `deletedAt IS NOT NULL`.

### Per-model table

| Model | Policy | Rationale |
| --- | --- | --- |
| User | **Soft-delete** | POPIA right to erasure: PII must be anonymisable on request. Cannot hard-delete while Objection records (legal) reference the user. Erasure = null out phone, email, displayName; set deletedAt. The User row remains as an anchor for Objection FK. |
| OTPAttempt | Hard delete (TTL purge) | Ephemeral security token. No legal retention obligation. Envelope specifies 30-day purge; implementation is a scheduled BullMQ job. |
| Property | Hard delete | Municipality master data — EasyRates does not own it. Sync from the municipality billing system overwrites rows; hard delete on resync is the correct pattern. |
| Account | **Soft-delete** | Follows User lifecycle. If User is soft-deleted, linked Accounts are soft-deleted in the same transaction. accountNumber must remain resolvable for historical Bill queries even after account closure. |
| Bill | Retain (never delete) | Financial record. SA financial regulations require 5-year retention of billing records. Municipality holds the truth; our copy is a cache subject to the same retention floor. No `deletedAt` column needed — records are never deleted. |
| BillLineItem | Retain (cascade from Bill) | Same retention reasoning as Bill. |
| AIAmountCalculation | Hard delete | Derived/operational data. No legal obligation. Cascades from BillLineItem via `onDelete: Cascade`. |
| ObjectionDraft | Hard delete | Transient. Deleted on submit (→ Objection created) or on 30-day abandonment purge. No audit obligation on pre-submission drafts. |
| Objection | **Soft-delete** | Legal record of a billing dispute submitted to the municipality. CANNOT be hard-deleted. Must persist even after User soft-delete. `onDelete: Restrict` on Objection.userId enforces this. |
| EvidenceFile | **Soft-delete** | Legal supporting document. The Azure Blob Storage file may be purged for storage cost, but the metadata row must be retained (filename, storageKey, uploadedAt) for audit. |
| MunicipalityResponse | **Soft-delete** | Legal record of the municipality's formal response. Required for TRACKING & RESOLUTION audit trail. |
| Notification | Hard delete (90-day retention purge) | Operational log. Envelope specifies 90-day rolling retention; purge is a scheduled BullMQ job. No legal obligation. |

### Schema patch

Add to User, Account, Objection, EvidenceFile, MunicipalityResponse:

```prisma
deletedAt DateTime?
```

### Query enforcement

All queries on soft-delete-enabled models MUST filter `deletedAt: null`. This is enforced
via Prisma query middleware in `shared/db.ts`, not per-handler — omitting the filter is
a bug category that middleware eliminates:

```typescript
prisma.$use(async (params, next) => {
  const SOFT_DELETE_MODELS = ['User', 'Account', 'Objection', 'EvidenceFile', 'MunicipalityResponse']
  if (SOFT_DELETE_MODELS.includes(params.model) && params.action === 'findMany') {
    params.args.where = { ...params.args.where, deletedAt: null }
  }
  return next(params)
})
```

AuditEvent is explicitly excluded from this middleware — audit logs are never soft-deleted.

### Costliest to reverse

Switching from hard-delete to soft-delete after go-live requires: (a) a migration adding
`deletedAt` to the table, (b) identifying and re-ingesting any already-deleted rows from
backups, (c) adding the global middleware. The data loss from (b) cannot be recovered if
no backup exists for the deletion window. This decision is medium-cost to reverse.

---

## DECISION-B: Audit Log Strategy

### Decision

**Manual AuditEvent model** with explicit `prisma.auditEvent.create()` calls in service
handlers after each auditable operation. Not Prisma middleware. Not an external package.

### Rejected options

**Prisma middleware** (`$use` hook): Intercepts writes only. `BILL_ACCESSED` is a READ
event — the most important POPIA obligation is logging financial data access, not just
writes. Middleware also has no access to HTTP request context (userId from JWT, IP address,
userAgent). Captures implementation detail (Prisma operation name) rather than semantic
event (`OBJECTION_STATUS_CHANGED`). Rejected.

**prisma-audit-trail package**: Same read-event limitation. Adds a dependency for ~50 lines
of implementation code. The package produces noisy logs (every `updatedAt` refresh creates
an entry). Rejected.

**Database triggers**: Cannot capture the requesting userId from the application layer —
only the database row values. Azure SQL trigger implementation is non-trivial to test and
debug. Rejected for a pilot-stage product.

### AuditEvent model

```prisma
model AuditEvent {
  id         String         @id @default(cuid())
  userId     String?
  event      AuditEventType
  entityId   String?
  entityType String?
  metadata   Json?
  createdAt  DateTime       @default(now())

  @@index([userId, createdAt])
  @@index([entityId, entityType])
}
```

`userId` is nullable: pre-authentication events (OTP_FAILED before login) have no userId.
`metadata` carries: IP address, userAgent, old/new status values, affected field names.
AuditEvent is **never soft-deleted** and never cascade-deleted. It is append-only.
If a User is anonymised, `userId` is set to null (SetNull) — the audit record survives,
the PII link is severed.

Projected row count: 300,000+/year (every login, every bill access, every OTP attempt).
Both indexes are justified by the 10k-row threshold: `@@index([userId, createdAt])` for
per-user audit history queries; `@@index([entityId, entityType])` for per-record history.

### Events that MUST be audited

| Event | Trigger | POPIA / Legal basis |
| --- | --- | --- |
| `BILL_ACCESSED` | `GET /bill?accountNumber=…` | POPIA: financial data access log required |
| `OBJECTION_SUBMITTED` | `POST /objections/:id/submit` | Legal: record of formal dispute creation |
| `OBJECTION_STATUS_CHANGED` | Any status transition on Objection | Legal: audit trail of dispute lifecycle |
| `EVIDENCE_UPLOADED` | `POST /objections/:id/evidence` | Legal: document attachment to formal dispute |
| `KYC_DOCUMENT_UPLOADED` | `POST /auth/kyc` | POPIA: special personal information (SA ID document) |
| `KYC_STATUS_CHANGED` | Municipality KYC webhook | POPIA: identity verification outcome |
| `USER_PII_ANONYMISED` | POPIA erasure request processing | POPIA: right to erasure — must log when and what was anonymised |
| `OTP_FAILED` | `POST /otp/verify` with wrong code | Security: evidence for rate-limit enforcement and breach detection |
| `LOGIN_FAILED` | `POST /auth/login` with wrong credentials | Security: breach detection |

Events that are useful but not obligatory (implemented at discretion):
`LOGIN_SUCCESS`, `MUNICIPALITY_RESPONSE_RECEIVED`, `PROPERTY_SEARCHED`.

### Downstream: plan/07 (security)

The AuditEvent model and the event list above are the authoritative audit surface for
plan/07's security design. plan/07 must not define its own audit events that conflict with
this list. If plan/07 identifies additional POPIA obligations requiring audit, the event
must be added to `AuditEventType` enum here first.

---

## DECISION-C: Multi-Tenancy

### Decision

**FK flag** — add `municipalityId String` to Property, Account, Bill, and Objection.
Add a `Municipality` model. Seed with one record (Emfuleni). No per-municipality schema
splitting in Phase 1.

### Rejected options

**No tenancy now (Option A)**: Adding `municipalityId` to 4 tables costs nothing at schema
creation time. Missing it means a migration touching 1M+ Bill rows and 5.4M+ BillLineItem
rows (via cascade) when the second municipality signs. The envelope projects Bill at 1.08M
rows at month 12. That migration is non-trivial and requires a maintenance window. Rejected.

**Separate schemas per municipality (Option C)**: Requires separate connection strings,
migration runs, and connection pools per tenant. Per-schema migration orchestration adds
operational overhead unjustified for a product with zero paying customers. Appropriate
if 3+ municipalities onboard with data-residency compliance requirements — this is the
documented upgrade path. Rejected for Phase 1.

### Municipality model

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

Seed value: `{ name: "Emfuleni Local Municipality", code: "EMFULENI" }`.

### Tables receiving municipalityId

| Table | Reason |
| --- | --- |
| Property | Properties belong to a municipality's valuation roll. Two municipalities may use overlapping ERF numbers. |
| Account | Account numbers are municipality-specific. Two municipalities can issue the same account number to different ratepayers. |
| Bill | Bills are issued by a specific municipality. |
| Objection | The formal dispute is against a specific municipality's charge. |

### Tables NOT receiving municipalityId

| Table | Reason |
| --- | --- |
| User | Users are global. A person can own property in two municipalities or move between them. |
| OTPAttempt | User-scoped, not municipality-scoped. |
| Notification, AuditEvent | Operational/user-scoped. Municipality is irrelevant to a push notification or login audit log. |
| EvidenceFile, MunicipalityResponse | Children of Objection. Municipality is inherited via `Objection.municipalityId` when needed. |
| AIAmountCalculation, BillLineItem | Children of Bill. Municipality inherited via `Bill.municipalityId`. |
| ObjectionDraft | Transient. Municipality not relevant until draft is submitted as Objection. |

### Phase 1 behaviour

All writes hard-code `municipalityId` to the Emfuleni seed ID. No query filtering by
`municipalityId` in Phase 1 service handlers — the value is always Emfuleni. When Phase 2
onboards a second municipality, service handlers add `where: { municipalityId: tenantId }`
using a `municipalityId` claim in the JWT. No schema migration required at Phase 2.

### Upgrade trigger

If three or more municipalities onboard AND data-residency compliance requires physical
isolation, migrate to per-schema tenancy at that point. The `municipalityId` FK becomes
the tenant discriminator for schema splitting. Azure SQL row-level security is also an
option — both are compatible with the FK already in place.

### Downstream: plan/08 (container topology)

plan/08 must not design for per-municipality containers or databases in Phase 1. The
single-database modular monolith (ADR-001 Decision F) stands. The Municipality seed record
is a `prisma db seed` step, not a container configuration concern.

---

## DECISION-D: Primary Key Type

### Decision

**CUID** — `String @id @default(cuid())` on all models. Applied to all 14 models
(12 original + Municipality + AuditEvent added by decisions A–C).

This decision overrides plan/01-user-auth.md's draft which used `@default(uuid())`.
UUID is replaced with CUID everywhere.

### Rejected options

**Auto-increment integer**: Sequential integers are enumerable. `GET /objections/1`,
`GET /objections/2` — a valid JWT holder can walk objection IDs and access records
belonging to other users. Objection data contains POPIA-classified financial information
and personal information. Sequential enumeration is a POPIA breach vector. Rejected.
Also reveals record counts to clients ("you are user 847"), which leaks business metrics.

**UUID** (`@default(uuid())`): Non-sequential and non-enumerable — equivalent security to
CUID. However, UUID requires the `pgcrypto` extension (`gen_random_uuid()`) in PostgreSQL
and Azure SQL. CUID is native to Prisma — no database extension needed. UUID is 36 chars
(with hyphens); CUID is 25 chars — smaller index entries and API payloads. UUID with
hyphens requires encoding in query strings. Rejected in favour of CUID; the security
properties are identical.

### CUID properties

- 25 characters. URL-safe without encoding.
- Non-sequential: not guessable or enumeratable.
- Collision-resistant at EasyRates scale (<<1M records/model).
- Prisma built-in: no `pgcrypto` extension, no custom default in PostgreSQL.
- Roughly time-ordered within the same millisecond — ORDER BY id approximates ORDER BY
  createdAt for short time windows. This is a minor benefit, not a guarantee.

### API contract implication

All `id` fields in every request and response schema are `string`. Clients MUST NOT parse,
sort, compare, or assume any structure in ID values beyond opaque string equality.
Example: `{ "objectionId": "clxxxxxxxxxxxxxxxxxxxxx" }`.

The `refNumber` field on Objection (`OBJ-2026-001`) is the human-readable case reference
shown in the UI and in email confirmations. It is separate from the PK and is generated
by the municipality adapter on successful submission.

### Downstream: plan/09 (API contracts)

Every `id`, `userId`, `billId`, `objectionId`, `lineItemId`, `accountId`, and
`municipalityId` field in every API contract MUST be typed as `string` (opaque). plan/09
must not use `integer` or `number` for any ID field. plan/01-user-auth.md's draft
`@default(uuid())` is superseded by this decision — update the contract if it references
UUID format validation.

---

## Schema patches required by these decisions

The four decisions add to the schema blocks produced in the FIELDS session. These patches
must be applied before `schema.prisma` is written.

### Patch 1: deletedAt fields (DECISION-A)

Add `deletedAt DateTime?` to: User, Account, Objection, EvidenceFile, MunicipalityResponse.

### Patch 2: AuditEvent model (DECISION-B)

New model added to schema. Not in original 12-entity list. Owned by auth-service
(written to by all services via `shared/db.ts`; no service owns a private audit table).
Projected rows: 300,000+/year — both indexes required.

### Patch 3: Municipality model + municipalityId fields (DECISION-C)

New model added to schema. `municipalityId String` added to Property, Account, Bill,
Objection with FK `→ Municipality.id` and `onDelete: Restrict` (cannot delete a
municipality while it has associated records).

### Patch 4: cuid() confirmed (DECISION-D)

No change to schema blocks from FIELDS session — all already use `@default(cuid())`.
Supersedes plan/01's draft `@default(uuid())`.

---

## Migration checklist (zero-downtime)

Every schema change after the initial `prisma migrate dev --name init` follows this
checklist. No migration may be applied to production without completing all steps.

**Step 1 — Generate without applying**
```bash
pnpm prisma migrate dev --create-only --name <descriptive_name>
```
Opens the generated `.sql` file. Review the SQL diff manually before proceeding.
Confirm: no DROP without a preceding data-migration step; no NOT NULL column added
without a DEFAULT or a two-phase deploy.

**Step 2 — Test on a production-equivalent snapshot**
Restore a recent production backup (or the Azure SQL dev instance) to a test environment.
Apply the migration:
```bash
DATABASE_URL=<test_url> pnpm prisma migrate deploy
```
Run the full integration smoke suite against the test environment. Zero failures required
before proceeding to production.

**Step 3 — Apply to production**
```bash
DATABASE_URL=<prod_url> pnpm prisma migrate deploy
```
`migrate deploy` (not `dev`) — applies pending migrations without regenerating or resetting.
Monitor Azure SQL DTU usage during the apply window.

**Step 4 — Verify**
```bash
pnpm prisma migrate status
```
Expected: "All migrations have been applied." Run smoke tests against production.
Check AuditEvent and Notification row counts to confirm no data was lost.

### Safe vs unsafe operations

| Operation | Safe? | Pattern |
| --- | --- | --- |
| Add nullable column | Safe — one deploy | `ALTER TABLE ADD COLUMN col TYPE NULL` |
| Add non-null column with DEFAULT | Safe — one deploy | `ALTER TABLE ADD COLUMN col TYPE NOT NULL DEFAULT val` |
| Drop a column | **Unsafe** | Two-phase: Phase 1 — stop reading/writing the column in code, deploy. Phase 2 — migrate to DROP the column. |
| Rename a column | **Unsafe** | Two-phase: Phase 1 — add new column, dual-write old+new in code, backfill, deploy. Phase 2 — drop old column. Never rename directly. |
| Add an index | Safe (locks briefly) | Apply during low-traffic window; `CREATE INDEX CONCURRENTLY` if supported. |
| Change column type | **Unsafe** | Requires new column, backfill, swap — treat as rename. |
| Add NOT NULL constraint to existing column | **Unsafe** | Backfill nulls first, then add constraint. |

---

## Revision history

| Date | Change | Author |
| --- | --- | --- |
| 2026-06-20 | Initial four decisions committed | System Design session |
