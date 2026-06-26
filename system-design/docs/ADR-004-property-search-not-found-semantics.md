# ADR-004 — Property search "not found" is `200` + null, not `404`

**Status:** Accepted (2026-06-22)
**Related:** Supersedes the `404 not_found` resolution for the **search** routes in
`api/property-service.md` (the original "deliberately ambiguous 404"). Builds on ADR-003 (the
identity gate whose ambiguity requirement this ADR preserves). Does **not** affect `GET
/property/:id`, which keeps `404`/`403`.

---

## Context

`POST /property/search/account` originally returned `404 not_found` (generic, deliberately
ambiguous) when the account did not exist **or** existed but failed the identity gate. The sibling
`POST /property/search/address` already returned `200 + []` on no match. So the two search routes
were asymmetric: one signalled "no match" through the status line, the other through the body.

For the FIND PROPERTY flow, "no match" is the **single most common user action** — a ratepayer
mistypes the 8-digit account number off their bill. The Flutter search screen must render this as a
normal "not found" UI state, not an error dialog. Routing the most common path through the HTTP
error channel (where Dio throws / non-2xx is caught as failure) forces the client to catch a `404`
and *re-classify* it as a normal state — brittle, and indistinguishable from the `404` that
infrastructure emits for a dead route, a misdeployed gateway, or a wrong API version.

The `404` was chosen for **security ambiguity** (never reveal "this account exists but is not
yours"), not because not-found is an error. That requirement is about *indistinguishability*, which
a `200` + null body satisfies just as well.

## Decision

The **search** routes report "no match" in the **body**, never in the status line.

1. **`POST /property/search/account`** → **`200`** with
   `{ "data": { "property": PropertySummaryResponse | null }, "error": null }`.
   - Match → `property` is the summary object.
   - No match → `property` is `null`.

2. **Ambiguity preserved (ADR-003).** The "account does not exist" case and the "exists but fails
   the identity gate" case return the **byte-identical** `{ "data": { "property": null }, "error":
   null }`. The client cannot distinguish them. `403` is **not** used on the search routes.

3. **`POST /property/search/address`** → unchanged: `200` + array, `[]` on no match. (ERF can map
   to multiple service accounts, so this route stays a collection — never a single object.)

4. **HTTP status is reserved for mechanical outcomes** on these routes: `200` (request succeeded —
   inspect the body for the business result), `400` (validation), `401` (auth), `429` (rate limit),
   `5xx` (server fault). A non-2xx is always a real error the client may surface as such.

5. **`GET /property/:id` is unaffected.** A concrete resource address keeps REST-conventional
   `404 not_found` (no such id, e.g. resync invalidated a stale id) and `403 forbidden` (id in hand,
   not authorized). The 200+null rule is for *query-by-parameter* lookups, not resource paths.

6. **Transport stays `POST`.** Account/ERF numbers are PII and the SEARCH routes are the enumeration
   surface (rate-limited 10/min, POPIA breach-by-enumeration). They must **not** move to `GET` with
   the identifier in the query string — that leaks PII into URLs, proxy logs, and browser history.
   This ADR changes only the *not-found semantics*, not the method.

## Consequences

**Positive**
- The Flutter client gets a clean two-axis read: HTTP status = "did it work?"; `property == null` =
  "valid not-found UI state". No catching-404-as-success.
- The two search routes are now consistent — both report no-match in the body.
- Security ambiguity is retained unchanged (null ≡ not-exist ≡ identity-miss).

**Costs / constraints**
- **Response shape change.** The `200` payload for account search is now wrapped as
  `{ property: ... | null }` rather than the bare `PropertySummaryResponse`. Any consumer reading
  the old bare shape must update. (No production client exists yet — the Flutter screen is a stub.)
- Clients must remember that `200` no longer guarantees a property; they must null-check
  `data.property`.

## Alternatives considered

- **Keep `404` (ambiguous).** Rejected — overloads `404` with infrastructure failures and forces
  not-found through the error channel; the security ambiguity it provided is equally available under
  `200` + null.
- **`GET /property?accountNumber=…` + `200`/null (combined `{property, account}`).** Rejected — `GET`
  puts PII in URLs (see Decision §6), a single-object response breaks ERF→many cardinality, and
  bundling property + account re-couples identity and balance (one response = one `Cache-Control`,
  forcing the whole payload onto the conservative no-store policy and crossing the
  property-service / account-service boundary). Balance is fetched separately on the confirmation
  screen.
- **`204 No Content` on no match.** Rejected — no body to carry the (deliberately null) result, and
  it conflates "empty" with the `204` already used for `DELETE` semantics elsewhere.

---

## Propagation this ADR requires

- `api/property-service.md` — restate the `not_found` central resolution; change `POST
  /property/search/account` to `200` + `{ property: ... | null }`; update its error table (drop the
  `404 not_found` row), TypeScript interfaces, and the Figma Trace "Not Found" rows.
