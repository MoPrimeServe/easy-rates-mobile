# EasyRates — Authorization Blast-Radius Audit

**Status:** Decided  
**Date:** 2026-06-20  
**Question answered:** If an attacker obtains a valid access token for user A, what can
they access?  
**Short answer:** Only user A's own accounts, properties, bills, objections, and
notifications — with two documented gaps in the property-service and four undocumented
endpoints in the status-service.

---

## Scope

37 Flutter-callable endpoints across 6 services. Internal-only endpoints
(`POST /notification/send`, `POST /status/:objectionRef/response`) are excluded from
the Flutter blast-radius — they require `X-Internal-Service-Secret` or
`X-Municipal-Webhook-Secret` headers that no Flutter client ever holds.

---

## The three Prisma scoping patterns

Every service handler MUST use one of these three patterns. A handler that does not use
one of these patterns is a scoping gap.

### Pattern 1 — Direct userId (profile, preferences, notifications)

Used when the table has a `userId` FK directly.

```typescript
// CORRECT
const profile = await prisma.user.findUniqueOrThrow({
  where: { id: req.user.id },
})

const notifications = await prisma.notification.findMany({
  where: { userId: req.user.id },
  orderBy: { sentAt: 'desc' },
  take: limit,
  skip: offset,
})
```

The WHERE clause includes `userId` as the primary filter. The JWT-extracted `req.user.id`
is the only acceptable source — never a caller-supplied `userId` body/query parameter.

### Pattern 2 — Ownership check before access (objection, evidence, bill detail)

Used when the client supplies a resource ID (`billId`, `objectionId`) and the handler
must confirm ownership before returning data.

```typescript
// CORRECT — single query: fetch WITH userId in WHERE
// A non-existent objection and a forbidden objection both return null → 404 (not 403)
// Returning 403 reveals that the resource exists; 404 is safer.
const objection = await prisma.objection.findFirst({
  where: { id: req.params.id, userId: req.user.id, deletedAt: null },
})
if (!objection) {
  return res.status(404).json({ data: null, error: { code: 'not_found' } })
}

// WRONG — two queries: fetch then check
const objection = await prisma.objection.findUnique({ where: { id: req.params.id } })
if (!objection) return res.status(404).json(...)
if (objection.userId !== req.user.id) return res.status(403).json(...) // reveals existence
```

The single-query form is both more efficient and more secure: it does not distinguish
"record doesn't exist" from "record exists but you don't own it," preventing the attacker
from probing for valid IDs belonging to other users.

### Pattern 3 — Ownership via chain traversal (bills, line items, anomalies, evidence)

`Bill` has no `userId` column. Ownership is established through the chain:
`Bill.accountNumber → Account.accountNumber → Account.userId`.

```typescript
// CORRECT — JOIN-based ownership assertion
const bill = await prisma.bill.findFirst({
  where: {
    id: req.params.billId,
    account: {
      userId: req.user.id,
      deletedAt: null,
    },
  },
})
if (!bill) {
  return res.status(404).json({ data: null, error: { code: 'not_found' } })
}

// NOTE: Bill.accountNumber is a soft reference (no DB FK to Account).
// Prisma cannot express this as a direct relation filter.
// The service layer must resolve manually:
const account = await prisma.account.findFirst({
  where: { accountNumber: bill.accountNumber, userId: req.user.id, deletedAt: null },
})
if (!account) {
  return res.status(404).json({ data: null, error: { code: 'not_found' } })
}
```

`BillLineItem`, `AIAmountCalculation`, and `EvidenceFile` are all reached through
`Bill` or `Objection` — any handler reading these must first validate the parent
Bill or Objection using Pattern 2 or 3 before fetching the child records.

### Pattern 4 — Property ownership (special case)

`Property` has no `userId`. Ownership is established via `Account`: a user "owns" a
property when they have an `Account` row with a matching `accountNumber` and
`deletedAt = null`.

```typescript
// CORRECT — for endpoints that require the property to be linked
async function assertOwnsProperty(userId: string, propertyId: string): Promise<Property> {
  const property = await prisma.property.findUnique({ where: { id: propertyId } })
  if (!property) throw new NotFoundError()

  const account = await prisma.account.findFirst({
    where: { userId, accountNumber: property.accountNumber, deletedAt: null },
  })
  if (!account) throw new NotFoundError() // 404, not 403 — same reason as Pattern 2

  return property
}

// Usage in bill-service: GET /bill?propertyId=
const property = await assertOwnsProperty(req.user.id, req.query.propertyId)
// proceed with bill queries using property.accountNumber
```

This utility (`assertOwnsProperty`) must be defined in `shared/authz.ts` and imported
by every service that accepts a `propertyId` parameter. The same pattern applies for
objection-service: `assertOwnsObjection(userId, objectionId)`.

---

## Endpoint-by-endpoint scoping table

### auth-service — all public endpoints; no user-data cross-access possible

| Endpoint | Auth | Scoping | Prisma pattern | Finding |
|---|---|---|---|---|
| `POST /auth/register/start` | public | Dispatches REGISTRATION OTP; 409 if phone taken | `findUnique({ where: { phone } })` | ✅ |
| `POST /auth/register` | public | Creates user; consumes registrationToken | — | ✅ |
| `POST /auth/login` | public | Always 200 (anti-enumeration); dispatches LOGIN OTP if phone exists | `findUnique({ where: { phone } })` | ✅ |
| `POST /auth/refresh` | public | Lookup by tokenHash | `findFirst({ where: { tokenHash: sha256(body.refreshToken) } })` | ✅ |
| `POST /auth/logout` | JWT | Revokes own token | `deleteMany({ where: { tokenHash, userId: req.user.id } })` | ✅ |
| `POST /auth/kyc` | JWT | Uploads to own KYC blob | `update({ where: { id: req.user.id } })` | ✅ |
| `GET /auth/session` | JWT | Validates own session | `findUnique({ where: { id: req.user.id, deletedAt: null } })` | ✅ |

**Note on `POST /otp/verify` and `POST /otp/resend`:** These are public and accept a
caller-supplied `userId`. An attacker cannot OTP-verify another user's session because
(a) the OTP code is bcrypt-hashed and single-use, (b) there is a 5-attempt lockout, and
(c) the attacker would need to know a valid pending `userId` + deliver a correct 6-digit
code within 10 minutes. The risk is accepted at pilot — if user enumeration via
`userId` becomes a concern, move these to require a JWT or a signed nonce from the
register/start or login response.

---

### account-service — Pattern 1 throughout; no gaps

| Endpoint | Prisma pattern | Finding |
|---|---|---|
| `GET /account/profile` | `findUniqueOrThrow({ where: { id: req.user.id } })` | ✅ |
| `PUT /account/profile` | `update({ where: { id: req.user.id } })` | ✅ |
| `GET /account/properties` | `findMany({ where: { userId: req.user.id, deletedAt: null } })` | ✅ |
| `POST /account/properties` | `create({ data: { userId: req.user.id, propertyId } })` | ✅ |
| `DELETE /account/properties/:propertyId` | `deleteMany({ where: { userId: req.user.id, propertyId } })` | ✅ |
| `GET /account/preferences` | `findUniqueOrThrow({ where: { id: req.user.id } })` | ✅ |
| `PUT /account/preferences` | `update({ where: { id: req.user.id } })` | ✅ |
| `GET /account/history` | `findMany({ where: { userId: req.user.id } })` | ✅ |
| `GET /account/objections` | `findMany({ where: { userId: req.user.id, deletedAt: null } })` | ✅ |

---

### bill-service — Pattern 3 (chain traversal) throughout; no gaps

All bill endpoints accept a `propertyId` or `billId`. Ownership is asserted via
`assertOwnsProperty(req.user.id, propertyId)` or the chain
`Bill → accountNumber → Account → userId`.

| Endpoint | Ownership assertion | Finding |
|---|---|---|
| `GET /bill?propertyId=` | `assertOwnsProperty(req.user.id, propertyId)` | ✅ |
| `GET /bill/:billId/line-items` | `assertOwnsProperty(req.user.id, bill.accountNumber)` | ✅ |
| `GET /bill/:billId/anomalies` | `assertOwnsProperty(req.user.id, bill.accountNumber)` | ✅ |
| `GET /bill/:billId/expected-amount` | `assertOwnsProperty(req.user.id, bill.accountNumber)` | ✅ |
| `POST /bill/:billId/review` | `assertOwnsProperty(req.user.id, bill.accountNumber)` | ✅ |

All bill endpoints return 404 (not 403) on cross-user access per Pattern 2 rationale.

---

### objection-service — Pattern 2 throughout; no gaps

| Endpoint | Ownership assertion | Finding |
|---|---|---|
| `POST /objection` | `assertOwnsProperty(req.user.id, propertyId)` + `assertOwnsBill(req.user.id, billId)` | ✅ |
| `GET /objection/:id` | `findFirst({ where: { id, userId: req.user.id } })` | ✅ |
| `POST /objection/:id/documents` | `assertOwnsObjection(req.user.id, objectionId)` | ✅ |
| `POST /objection/:id/submit` | `assertOwnsObjection(req.user.id, objectionId)` | ✅ |
| `GET /objections/:id/summary` | `findFirst({ where: { id, userId: req.user.id } })` | ✅ |

```typescript
// shared/authz.ts — required utility
export async function assertOwnsObjection(
  userId: string,
  objectionId: string,
): Promise<Objection> {
  const objection = await prisma.objection.findFirst({
    where: { id: objectionId, userId, deletedAt: null },
  })
  if (!objection) throw new NotFoundError()
  return objection
}
```

---

### notification-service — Pattern 1; no gaps

| Endpoint | Prisma pattern | Finding |
|---|---|---|
| `GET /notification/history` | `findMany({ where: { userId: req.user.id } })` | ✅ |
| `POST /notification/send` | Internal only — `X-Internal-Service-Secret` required | ✅ |

---

### status-service — Pattern 2 via refNumber; partial gaps (see flags below)

| Endpoint | Ownership assertion | Finding |
|---|---|---|
| `GET /status/:objectionRef` | `findFirst({ where: { refNumber, userId: req.user.id } })` | ✅ |
| `POST /status/:objectionRef/response` | Internal — `X-Municipal-Webhook-Secret` | ✅ |
| `POST /objections/:ref/probe` | **Undocumented** | ⚠️ |
| `POST /objections/:ref/escalate` | **Undocumented** | ⚠️ |
| `POST /objections/:ref/close` | **Undocumented** | ⚠️ |
| `POST /objections/:id/documents` (status) | **Undocumented** | ⚠️ |

---

### property-service — ⚠️ TWO GAPS

Property is the only service with confirmed cross-user data exposure. Both gaps stem from
the "find my property before linking" flow — users must discover their property by
account number or address before they can link it. This is intentional UX, but the
response payload exposes third-party PII.

| Endpoint | Ownership check? | Cross-user data exposed | Finding |
|---|---|---|---|
| `GET /property?accountNumber=` | None | `owner` (ownerName — third-party PII), `address` | ⚠️ **GAP** |
| `GET /property/search?q=` | None | `address`, `accountNumber` | ⚠️ **PARTIAL** |
| `GET /property/:id` | `assertOwnsProperty` (403 if not linked) | None | ✅ |
| `GET /property/:id/pdf` | Undocumented (not in api/property.md) | Unknown | ⚠️ |
| `POST /property/link` | Scoped to req.user.id (creates Account) | None | ✅ |

---

## Flagged gaps

### GAP-1: `GET /property?accountNumber=` exposes third-party `owner` name

**What happens:** Any authenticated user who knows any account number (e.g., reads
a neighbour's rates bill) can call this endpoint and receive the registered owner's
full name (`Property.ownerName`) and address — PII belonging to that third party.

**POPIA implication:** `Property.ownerName` is classified as PII in
`popia-inventory.md`. Returning it to an unauthenticated requester (anyone with a
valid token, not necessarily the owner) violates the minimum-necessary principle.

**Design intent vs actual risk:**  
The account number is the knowledge factor — "only the property owner knows their
account number." In practice account numbers appear on water bills, council invoices,
and notices that may be shared or discarded. The knowledge factor is weak.

**Fix — two options (choose in plan/09):**

Option A — Remove `owner` from this response:
```json
// Response without owner field — sufficient to confirm it's the right property
{
  "id": "uuid",
  "accountNumber": "ACC001",
  "address": "123 Main Street, Vereeniging",
  "erfNumber": "ERF/001/VRG",
  "ward": "Ward 12",
  "zone": "Residential A"
  // owner removed — user confirms by recognising their address, not seeing their name
}
```

Option B — Add a soft ownership gate (only show `owner` if the account number matches
a linked Account for the requesting user):
```typescript
const isLinked = await prisma.account.findFirst({
  where: { userId: req.user.id, accountNumber: property.accountNumber, deletedAt: null },
})
return isLinked
  ? { ...property, owner: property.ownerName }  // linked: show owner name
  : { ...property, owner: null }                  // not yet linked: omit
```

**Recommendation: Option A** — remove `owner` from this pre-link response. The user
confirms the property by recognising their own address. The name is only needed
post-link. This is a one-line response-shape change.

---

### GAP-2: `GET /property/search?q=` returns unowned properties (lower risk)

**What happens:** Any authenticated user can search for any address or ERF number and
receive a list including `accountNumber` and `address` for properties they don't own.

**Lower risk than GAP-1** because: (a) the search results do not include `owner`
(ownerName) — only address and ERF number, which are public cadastral records;
(b) account numbers in search results are a mild PII exposure since they could be used
as the input to GAP-1.

**Fix:** If GAP-1 is fixed by removing `owner` from the response, the marginal risk of
GAP-2 is: an attacker can harvest account numbers to build an enumeration list. Rate
limiting at SEARCH tier (10/min/userId) caps bulk enumeration.

**Disposition:** Accept at pilot pending GAP-1 fix. Before production, evaluate whether
`accountNumber` should be redacted in search results (replace with a cursor token that
expires after the property is confirmed and linked).

---

### GAP-3: `GET /property/:id/pdf` — no scoping documentation

`service-map.md` references `GET /property/:id/pdf` but `api/property.md` does not
document this endpoint or its error responses. If this endpoint is implemented, it must
apply `assertOwnsProperty(req.user.id, propertyId)` before generating and streaming the
PDF — a PDF of another user's property statement is a more serious data leak than a JSON
response.

**Required action:** Document this endpoint in `api/property.md` with explicit 403
handling before plan/09 is closed.

---

### GAP-4: Four status-service endpoints — no scoping documentation

`service-map.md` references these endpoints but `api/status.md` only documents two:

| Missing endpoint | Required scoping |
|---|---|
| `POST /objections/:ref/probe` | `assertOwnsObjection(req.user.id, objectionId)` |
| `POST /objections/:ref/escalate` | `assertOwnsObjection(req.user.id, objectionId)` |
| `POST /objections/:ref/close` | `assertOwnsObjection(req.user.id, objectionId)` |
| `POST /objections/:id/documents` | `assertOwnsObjection(req.user.id, objectionId)` |

All four must be documented in `api/status.md` with explicit ownership assertions and 404
error responses before plan/09 is closed.

---

## Shared authz utilities required before plan/09 closes

These four functions must live in `shared/authz.ts` and be imported — never
re-implemented — in each service handler:

```typescript
// shared/authz.ts

export async function assertOwnsProperty(
  userId: string,
  propertyId: string,
): Promise<Property> {
  const property = await prisma.property.findUnique({ where: { id: propertyId } })
  if (!property) throw new NotFoundError()
  const account = await prisma.account.findFirst({
    where: { userId, accountNumber: property.accountNumber, deletedAt: null },
  })
  if (!account) throw new NotFoundError() // 404, not 403
  return property
}

export async function assertOwnsBill(
  userId: string,
  billId: string,
): Promise<Bill> {
  const bill = await prisma.bill.findUnique({ where: { id: billId } })
  if (!bill) throw new NotFoundError()
  const account = await prisma.account.findFirst({
    where: { userId, accountNumber: bill.accountNumber, deletedAt: null },
  })
  if (!account) throw new NotFoundError()
  return bill
}

export async function assertOwnsObjection(
  userId: string,
  objectionId: string,
): Promise<Objection> {
  const objection = await prisma.objection.findFirst({
    where: { id: objectionId, userId, deletedAt: null },
  })
  if (!objection) throw new NotFoundError()
  return objection
}

export async function assertOwnsObjectionByRef(
  userId: string,
  refNumber: string,
): Promise<Objection> {
  const objection = await prisma.objection.findFirst({
    where: { refNumber, userId, deletedAt: null },
  })
  if (!objection) throw new NotFoundError()
  return objection
}
```

**Critical:** All utilities return 404 (not 403) on ownership failure. This is intentional:
returning 403 confirms to an attacker that the resource exists under a different owner.
Returning 404 gives no information about existence.

---

## Blast-radius verdict

**Token for user A gives access to:**

| Resource | Accessible? | How scoped |
|---|---|---|
| User A's profile, email, phone | ✅ Yes | Pattern 1 — `userId = req.user.id` |
| User A's linked properties | ✅ Yes | Pattern 1 — `userId = req.user.id` |
| User A's bills and line items | ✅ Yes | Pattern 3 — chain via `accountNumber` |
| User A's objections | ✅ Yes | Pattern 2 — `userId = req.user.id` |
| User A's evidence files | ✅ Yes | Via `assertOwnsObjection` |
| User A's notifications | ✅ Yes | Pattern 1 — `userId = req.user.id` |
| User A's objection status | ✅ Yes | Pattern 2 via refNumber |
| **User B's profile** | ❌ No | No endpoint accepts `userId` param |
| **User B's bills** | ❌ No | `assertOwnsProperty` blocks |
| **User B's objections** | ❌ No | `findFirst({ userId: req.user.id })` blocks |
| **User B's owner name** | ⚠️ **Yes (GAP-1)** | `GET /property?accountNumber=` has no check |
| **User B's address** | ⚠️ **Yes (GAP-2)** | Via property search |
| Admin endpoints | ❌ No | No admin routes exist in this design |
| Internal-service endpoints | ❌ No | `X-Internal-Service-Secret` required |
| List of all users | ❌ No | No such endpoint exists |

**Conclusion:** Blast radius is confirmed user-scoped for all account, bill, objection,
notification, and status data. Two gaps in property-service allow a stolen token to
read third-party owner names and addresses. GAP-1 is the higher-priority fix (removes
PII from response); GAP-2 is acceptable at pilot given rate limiting.

---

## Required actions before plan/09 closes

| # | Action | File | Owner |
|---|---|---|---|
| A1 | Remove `owner` field from `GET /property?accountNumber=` response | `api/property.md` | architect → dev |
| A2 | Document `GET /property/:id/pdf` with `assertOwnsProperty` 403 | `api/property.md` | architect |
| A3 | Document `POST /objections/:ref/probe` with ownership assertion | `api/status.md` | architect |
| A4 | Document `POST /objections/:ref/escalate` with ownership assertion | `api/status.md` | architect |
| A5 | Document `POST /objections/:ref/close` with ownership assertion | `api/status.md` | architect |
| A6 | Document `POST /objections/:id/documents` (status) with ownership assertion | `api/status.md` | architect |
| A7 | Create `shared/authz.ts` with four utility functions above | `backend/shared/authz.ts` | dev |
| A8 | Every service handler must import from `shared/authz.ts` — never reimplement | `backend/src/modules/*/handlers` | dev (code review gate) |
