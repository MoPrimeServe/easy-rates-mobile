# ADR-005 — Property address search: substring `LIKE`, not Azure SQL full-text

**Status:** Accepted (2026-06-22)
**Related:** ADR-003 (identity gate — the fact this decision leans on). Refines the matching
semantics of `POST /property/search/address` in `api/property-service.md`.

---

## Context

`POST /property/search/address` lets a ratepayer find a property by a free-text address (`q`) or
ERF number to link it. Free-text search over a large text column usually argues for **Azure SQL
full-text search** (a full-text catalog + index, queried with `CONTAINS`/`FREETEXT`) — because a
leading-wildcard `LIKE '%q%'` is non-SARGable and table-scans, which is slow at scale.

But this search is **identity-gated** (ADR-003): results are restricted to properties where
`user.idNumberHash ∈ property.holderIdNumberHashes`. A person is a registered holder of only a
handful of properties. So the endpoint never searches the full municipal roll — it searches the
requesting user's own holdings, a candidate set of <~10 rows.

## Decision

1. **`q` → partial, case-insensitive substring match** (`LIKE '%q%'`) across the physical-address
   fields. Minimum 3 characters. Returns `0..n`.
2. **`erfNumber` → exact, normalized match** (case-insensitive, whitespace-stripped) — it is an
   identifier, not free text. Returns `0..1`.
3. **No Azure SQL full-text search at MVP.** The gate pre-filters to the user's few rows before the
   `LIKE` runs, so the non-SARGable scan touches a trivial number of rows. A full-text catalog
   (population lag, index maintenance, extra Azure surface) buys nothing at this scale.
4. **Exact-match for `q` is rejected** — hostile UX; the user would have to type the full normalized
   address. Partial is forgiving (e.g. "12 Vaal" finds "12 Vaal Street, Vereeniging").

## Consequences

**Positive**
- No full-text infrastructure to provision or maintain for the pilot.
- Forgiving address UX with a deterministic, easily-tested matcher.

**Costs / constraints**
- `LIKE '%q%'` is non-SARGable; acceptable **only** because the gate bounds the row count. If the
  gate were ever removed or widened, this scan would degrade.
- No typo tolerance / ranking / stemming. Fine for picking from one's own handful of properties;
  not fine for a broad search.

## Revisit trigger

Introduce Azure SQL full-text (or a trigram/`pg_trgm`-style index on the chosen store) **iff** an
**un-gated** property search is added — e.g. a municipal staff/admin console searching the whole
property roll. That is out of scope for the ratepayer MVP. Until then, `LIKE` stands.
