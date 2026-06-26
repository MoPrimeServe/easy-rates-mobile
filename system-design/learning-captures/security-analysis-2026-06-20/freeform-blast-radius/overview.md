# freeform: Blast-Radius Endpoint Audit
Session: security-analysis-2026-06-20

The blast-radius question: if an attacker obtains a valid JWT access token for user A,
what can they access?

Expected answer: only user A's own accounts, properties, bills, and objections. The audit
verified this for 37 endpoints across 9 services and found two gaps.

---

## The four Prisma scoping patterns

Every endpoint must use one of these four patterns. No endpoint may implement its own
ownership check. All four belong in `shared/authz.ts` (see action A7 below).

### Pattern 1 — Direct userId

Used when the model has a `userId` column that directly references the authenticated user.

```typescript
// User profile — always the requesting user's own row
const profile = await prisma.user.findUniqueOrThrow({
  where: { id: req.user.id },
})

// Notifications — always the requesting user's
const notifications = await prisma.notification.findMany({
  where: { userId: req.user.id },
})
```

**Models that use this pattern:** User, Notification, ObjectionDraft, Account.

The `where: { userId: req.user.id }` clause is the entire ownership control. It is
correct and sufficient when the model has a direct FK to User.

### Pattern 2 — Single-query ownership check (404 not 403)

Used when fetching a specific resource by ID. The ownership check is folded into the
same query as the fetch. This is the critical security distinction.

```typescript
// CORRECT: null for non-existent AND forbidden — both → 404
const objection = await prisma.objection.findFirst({
  where: {
    id: req.params.id,
    userId: req.user.id,
    deletedAt: null,
  },
})
if (!objection) return res.status(404).json({ data: null, error: { code: 'not_found' } })
// ← attacker cannot tell if the objection doesn't exist or belongs to someone else
```

```typescript
// WRONG: two-step — fetch then check ownership separately
const objection = await prisma.objection.findUnique({ where: { id: req.params.id } })
if (!objection) return res.status(404).json(...)  // ← first 404 leaks non-existence
if (objection.userId !== req.user.id) return res.status(403).json(...)
//   ↑ 403 here leaks existence to the attacker (404 earlier, 403 now → resource exists)
```

**Why 404 not 403 matters:**

An attacker who receives 403 knows the resource exists and belongs to someone else. They
can enumerate all resource IDs (UUIDs are not secret — they appear in network traffic,
logs, and support tickets). With the two-step pattern, `GET /objection/abc123` returns:
- 404 → does not exist (or was deleted)
- 403 → exists, belongs to someone else ← information leak

With the single-query pattern, both cases return 404. The attacker learns nothing about
whether the resource exists.

**Models that use this pattern:** Objection (by ID), EvidenceFile (by ID), Bill (by ID
after chain traversal — see Pattern 3).

### Pattern 3 — Bill chain traversal (no direct userId FK on Bill)

`Bill` has `accountNumber: String` as a **soft reference** to Account. There is no Prisma
relation (no `@relation` directive, no FK in the database). Ownership must be proven
through Account.

```typescript
async function assertOwnsBill(userId: string, billId: string): Promise<Bill> {
  // Step 1: fetch the bill
  const bill = await prisma.bill.findUnique({ where: { id: billId } })
  if (!bill) throw new NotFoundError()

  // Step 2: verify the account it belongs to is owned by this user
  const account = await prisma.account.findFirst({
    where: {
      userId,
      accountNumber: bill.accountNumber,
      deletedAt: null,
    },
  })
  if (!account) throw new NotFoundError() // 404 not 403 — same rule applies
  return bill
}
```

**Why two queries, not one:**
There is no Prisma relation between Bill and Account. Prisma's nested `include`/`where`
works through defined relations. Since `Bill.accountNumber` is a plain String field (not
a FK), the join must be done manually in application code.

**Why not `prisma.account.findFirst({ include: { bills: ... } })`:**
That would require the relation to exist in the schema. It doesn't — the account number
linkage is intentionally a soft reference (the municipality's account numbers may not be
stable UUIDs and may need to be updated without cascading).

**Models that use this pattern:** Bill, BillLineItem (via Bill).

### Pattern 4 — Property ownership chain (no userId on Property)

`Property` has no `userId` column. Ownership is established through Account:
`User → Account.userId` + `Account.accountNumber = Property.accountNumber`.

```typescript
async function assertOwnsProperty(userId: string, propertyId: string): Promise<Property> {
  // Step 1: fetch the property
  const property = await prisma.property.findUnique({ where: { id: propertyId } })
  if (!property) throw new NotFoundError()

  // Step 2: verify the user has a linked account with this account number
  const account = await prisma.account.findFirst({
    where: {
      userId,
      accountNumber: property.accountNumber,
      deletedAt: null,
    },
  })
  if (!account) throw new NotFoundError() // 404 not 403
  return property
}
```

**Why `property.accountNumber` is the join key:**
Property is linked to Account via `accountNumber`. A user "owns" a property in the
EasyRates sense when they have an Account whose `accountNumber` matches the Property's
`accountNumber`. The municipality's system of record (which produced the Property record)
uses account numbers as the linking mechanism, not user IDs.

---

## Required `shared/authz.ts` utilities

These four functions encapsulate every ownership check in the application. Every service
handler imports from this module. No handler re-implements the check locally.

```typescript
// shared/authz.ts

export async function assertOwnsProperty(
  userId: string,
  propertyId: string,
): Promise<Property>
// → throws NotFoundError (HTTP 404) if property does not exist OR user does not own it

export async function assertOwnsBill(
  userId: string,
  billId: string,
): Promise<Bill>
// → throws NotFoundError (HTTP 404) if bill does not exist OR account link not found

export async function assertOwnsObjection(
  userId: string,
  objectionId: string,
): Promise<Objection>
// → throws NotFoundError (HTTP 404) if objection does not exist OR userId does not match

export async function assertOwnsObjectionByRef(
  userId: string,
  refNumber: string,
): Promise<Objection>
// → same, but lookup by refNumber instead of UUID
// → needed for status-service endpoints that use refNumber as the path parameter
```

**Why 404 everywhere (not 403):** All four throw `NotFoundError`, which maps to HTTP 404.
This is intentional and consistent: ownership failure is indistinguishable from
non-existence from the client's perspective.

**Import rule (action A8):** Every endpoint handler that touches a Property, Bill,
Objection, or EvidenceFile MUST import its assertion from `shared/authz.ts`. It must
never re-implement the check. Code review must enforce this — searching for
`prisma.property.findUnique({ where: { id` outside of `shared/authz.ts` is a smell.

---

## Blast-radius verdict table

| Resource | Accessible with user A's token? |
| --- | --- |
| User A's profile | ✅ Yes — `prisma.user.findUniqueOrThrow({ where: { id: req.user.id } })` |
| User A's accounts | ✅ Yes — `{ userId: req.user.id }` |
| User A's properties | ✅ Yes — assertOwnsProperty verifies Account link |
| User A's bills | ✅ Yes — assertOwnsBill verifies Account link via accountNumber |
| User A's objections | ✅ Yes — `{ id, userId: req.user.id }` |
| User A's evidence files | ✅ Yes — scoped through objection ownership |
| User A's notifications | ✅ Yes — `{ userId: req.user.id }` |
| User B's profile | ❌ No |
| User B's bills, objections | ❌ No |
| User B's owner name (Property.ownerName) | ⚠️ Yes — GAP-1 |
| Admin endpoints | ❌ No — no admin endpoints exist in the current design |
| Internal-service endpoints | ❌ No — `X-Internal-Service-Secret` header required |
| List of all users | ❌ No — no such endpoint exists |

---

## GAP-1 (HIGH): `GET /property?accountNumber=` returns third-party PII

**What it does:** Allows an authenticated user to look up a property by account number
before linking it to their account. This is the "find-before-link" UX: the user searches
for their property, confirms it is theirs, then links it.

**The leak:** The response includes `owner: "Jane Doe"` — the value of
`Property.ownerName`. This is the name of the **owner of record**, who may be a
third party (a landlord, a deceased prior owner, a property management company). The
requesting user did not consent to share this person's name with EasyRates. The owner
did not consent either.

**Who can exploit it:** Any authenticated user who knows any valid account number can
retrieve the owner's full name and address. Account numbers are not secret — they appear
on utility bills, tenant agreements, and municipality correspondence.

**Fix A (recommended):** Remove `owner` from the pre-link response. The user can confirm
the property is theirs by recognising the address, not the owner name.

```diff
// api/property.md — GET /property?accountNumber= response
  "data": {
    "id": "...",
    "address": "12 Erf Street, Sebokeng",
    "accountNumber": "ACC-0042",
-   "owner": "Jane Doe",
    "linked": false
  }
```

**Fix B (soft gate — if Fix A is not acceptable UX):** Return `owner` only when the
requesting user has a linked Account with the same accountNumber. This confirms the user
already has access rights to the property before exposing the owner name.

**Decision needed before plan/09:** Which fix is applied must be recorded in
`api/property.md` as the authoritative API contract.

---

## GAP-2 (LOW): `GET /property/search?q=` returns address + accountNumber

**What it does:** Free-text property search. Returns address and accountNumber for
matching properties.

**The exposure:** Any authenticated user can search for any property. The returned
address and account number constitute PII for the property's owner/occupant. However,
this data is arguably lower-sensitivity than `ownerName` (addresses and account numbers
appear in public rates rolls in South Africa).

**Mitigating control:** Rate-limited at 10 requests/minute/userId. This limits scraping.

**Accepted at pilot:** If GAP-1 is fixed (removing `ownerName` from all pre-link
responses), GAP-2 is accepted for the pilot. The reasoning: address lookups are a core
feature (you have to be able to find your property), and addresses are not the same
sensitivity level as a person's full name.

**Go-live review:** Before production, revisit whether the search surface needs
authentication strengthening (e.g., search only returns properties in the user's
municipality zone, not all properties nationally).

---

## GAP-3: `GET /property/:id/pdf` undocumented

Referenced in `service-map.md` under the property service but not documented in
`api/property.md`. The ownership assertion required is `assertOwnsProperty` (Pattern 4).

**Action A2:** Add `GET /property/:id/pdf` to `api/property.md` with:
- ownership assertion: `assertOwnsProperty(req.user.id, req.params.id)`
- response: `application/pdf` binary (204 or 200 with content-disposition)
- error: 404 if property not found or not owned by requesting user

---

## GAP-4: Four undocumented status-service endpoints

Found in `service-map.md` and `rate-limits.md` but absent from `api/status.md`:

| Endpoint | Ownership assertion needed |
| --- | --- |
| `POST /objections/:ref/probe` | `assertOwnsObjectionByRef(req.user.id, req.params.ref)` |
| `POST /objections/:ref/escalate` | `assertOwnsObjectionByRef(req.user.id, req.params.ref)` |
| `POST /objections/:ref/close` | `assertOwnsObjectionByRef(req.user.id, req.params.ref)` |
| `POST /objections/:id/documents` | `assertOwnsObjection(req.user.id, req.params.id)` |

Note: three use `refNumber` as the path parameter (`:ref`), one uses UUID (`:id`).
This is why `assertOwnsObjectionByRef` is a separate utility — the lookup key differs.

**Actions A3–A6:** Document all four in `api/status.md` with the ownership assertion
and request/response shape.

---

## Endpoint naming discrepancy (must resolve before plan/09)

Two sources use different names for the same endpoint:

- `api/objection.md` → `POST /objection/:id/documents`
- `service-map.md` and `rate-limits.md` → `POST /objections/:id/evidence`

These differ in both path prefix (`/objection` vs `/objections`) and resource name
(`documents` vs `evidence`). One of these must be authoritative. The API contract
(`api/objection.md`) is the intended source of truth. The service-map and rate-limits
must be updated to match, or the API contract must be revised — but they cannot differ
when plan/09 closes.

---

## Action items before plan/09 closes (A1–A8)

| # | Action | File |
| --- | --- | --- |
| A1 | Remove `owner` from `GET /property?accountNumber=` response | `api/property.md` |
| A2 | Document `GET /property/:id/pdf` with assertOwnsProperty | `api/property.md` |
| A3 | Document `POST /objections/:ref/probe` | `api/status.md` |
| A4 | Document `POST /objections/:ref/escalate` | `api/status.md` |
| A5 | Document `POST /objections/:ref/close` | `api/status.md` |
| A6 | Document `POST /objections/:id/documents` | `api/status.md` |
| A7 | Create `shared/authz.ts` with 4 utility functions | `shared/authz.ts` |
| A8 | Enforce import pattern in code review | Convention, not file |

These are tracked in `easy_rates/system-design/docs/security/authorization.md`.
