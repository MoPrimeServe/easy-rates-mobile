# ADR-003 — SA ID number stored as a keyed hash (property identity gate)

**Status:** Accepted (2026-06-21)
**Related:** ADR-002 (passwordless OTP-first) surfaced this — `idNumber` is required on register
but `docs/data-model/user-auth.md` has no SA-ID column, yet `api/property-service.md` gates every
property search on `user.idNumber ∈ property.holderIdNumbers` server-side.

---

## Context

`POST /auth/register` collects and Luhn-validates a 13-digit SA ID number, but the contract says
it is **validated, not stored** — there is no column on `User`. The property-service identity gate,
however, needs the user's ID number **server-side at link time** to test membership against a
property's holder records (`user.idNumber ∈ property.holderIdNumbers`). Validate-then-discard
cannot feed that gate: by link time there is nothing to match.

So the ID number must be persisted in *some* form. SA ID numbers are **special personal
information** under POPIA, and their effective entropy is low (the 13 digits encode date of birth +
sequence + citizenship + a Luhn check digit), so naive storage is a real breach risk.

The gate only ever needs **equality / set membership** — it never needs to read the ID back.

## Decision

Persist the SA ID **only as a keyed one-way hash**, never in plaintext, and match the gate on
hashes.

1. **`User.idNumberHash String?`** — HMAC-SHA256 of the normalized ID, hex-encoded. Nullable so it
   can be nulled on POPIA erasure. Going forward every registered user has it (register requires
   `idNumber`).

2. **Keyed hash, not a plain digest or bcrypt.**
   - `idNumberHash = HMAC_SHA256(pepper, normalize(idNumber))`, hex.
   - `normalize` = strip non-digits; must be exactly 13 digits and Luhn-valid before hashing.
   - **bcrypt/argon2 are rejected here** — per-value random salts make two hashes of the same ID
     differ, which breaks set-membership matching. We need a *deterministic* keyed hash.
   - The **pepper** (`ID_NUMBER_HMAC_PEPPER`) lives in the KMS / secret store, **never in the
     database**. A DB-only breach therefore cannot brute-force the low-entropy ID space without
     also stealing the pepper.

3. **Property side: store hashes, discard plaintext.** At municipal sync, compute
   `Property.holderIdNumberHashes String[]` = `HMAC_SHA256(pepper, normalize(h))` for each holder ID
   `h` in the export, and **do not persist the plaintext holder IDs**. (Minimization — EasyRates
   never needs to display them.)

4. **The gate becomes a hash set-membership test:**
   `user.idNumberHash ∈ property.holderIdNumberHashes`. The client still never sends an ID number;
   the comparison is server-side, hash-to-hash.

5. **Register** computes the HMAC, stores `idNumberHash`, and discards the plaintext within the
   request — the plaintext ID is never written to the DB or logs.

## Consequences

**Positive**
- The property identity gate actually works (it was unsatisfiable before).
- No plaintext SA ID at rest anywhere; only keyed hashes. POPIA data-minimization is satisfied.
- A DB breach alone does not expose IDs (pepper is out-of-band).

**Costs / constraints**
- **New secret to manage:** `ID_NUMBER_HMAC_PEPPER` (KMS, access-controlled, audited).
- **Pepper rotation is hard.** Rotating the pepper invalidates every stored `idNumberHash`. Property
  hashes can be recomputed on the next municipal sync (plaintext arrives again from the export), but
  **`User.idNumberHash` cannot be re-derived** — the user's plaintext was discarded. Rotation would
  therefore force affected users to re-supply their ID. **Decision: treat the pepper as long-lived;**
  rotate only on compromise, and on rotation require ID re-entry (a one-time re-verify step). The
  alternative — reversible encryption to allow re-hash without re-collection — is rejected because it
  reintroduces recoverable PII at rest (see Alternatives).
- **Residual brute-force risk:** SA ID entropy is low, so anyone holding *both* the DB and the pepper
  could enumerate. Mitigation is purely the pepper's confidentiality (KMS). Acceptable for pilot;
  revisit if the threat model hardens.
- `idNumberHash` is **pseudonymised special PI** — it must appear in the POPIA inventory and be
  nulled on erasure.

## Alternatives considered

- **Store plaintext `idNumber`.** Rejected — POPIA minimization; worst breach exposure.
- **Reversible encryption (AES-GCM with a KMS key).** Allows pepper/key rotation without
  re-collection, but keeps recoverable special PI at rest. Rejected for storage; kept as the
  documented fallback *iff* pepper rotation becomes a hard operational requirement.
- **bcrypt/argon2 salted hash.** Rejected — salts defeat the set-membership match the gate needs.
- **Don't store; re-collect the ID at link time and match against the property's plaintext holder
  IDs.** Rejected — worse UX, and it forces the *property* side to keep plaintext holder IDs (more
  special PI at rest), which this decision specifically avoids.

---

## Propagation this ADR requires (if accepted)

- `docs/data-model/user-auth.md` — add `idNumberHash String?` to `User` (+ field table, POPIA
  erasure list).
- `docs/data-model/property-account.md` — `Property.holderIdNumberHashes String[]`; drop any
  plaintext holder-ID column.
- `api/property-service.md` — restate the identity gate as a hash set-membership test.
- `api/auth-service.md` — register note: ID stored as keyed hash, plaintext discarded.
- `docs/security/popia-inventory.md` — add `User.idNumberHash` (pseudonymised special PI) + pepper.
