# freeform: POPIA Field Classification
Session: security-analysis-2026-06-20

---

## The classification framework

Five tiers, in descending protection level:

| Code | Meaning | POPIA category |
| --- | --- | --- |
| SPI | Special Personal Information | §26 — stricter obligations, highest risk |
| PII | Personal Information | General personal info |
| FIN | Financial | Billing amounts, arrears, estimates |
| OPS | Operational | Reference numbers, status, timestamps |
| NS | Non-sensitive | Internal UUIDs, boolean flags |

The distinction between SPI and PII is load-bearing for control choices. SPI under
POPIA §26 includes: race, gender, sexual orientation, pregnancy, national origin,
**identity documents** (SA ID number, passport, biometric data), religious belief,
trade union membership, health information, criminal record, and child information.

SA identity documents are SPI because they are **biometric-adjacent**: the SA ID number
encodes date of birth and gender, enables SIM swap, enables bank account impersonation,
and enables credit fraud. A leak of a SA ID number is not a data breach — it is an
identity takeover vector.

---

## Breach notification obligations

Under POPIA:

- **Notification timeline**: "as soon as reasonably possible" — the Information Regulator
  interprets this as ≤72 hours, aligning with GDPR practice.
- **Who to notify**: the Information Regulator AND the affected data subjects.
- **Maximum penalty**: R10,000,000 (R10M) or 10 years imprisonment for a responsible party.
- **Responsible party**: Emfuleni Local Municipality (not PrimeServe). EasyRates processes
  data on behalf of the municipality. The municipality bears the legal obligation; EasyRates
  must make compliance possible.

---

## The two Special Personal Information fields

### `User.kycDocumentKey` — **SPI** (highest risk in the data model)

An Azure Blob Storage key pointing to a copy of the user's SA identity document (ID book
or smart card image), uploaded during KYC verification.

**Risk if leaked:**
- Attacker retrieves the SA ID document from Blob using the key.
- SA ID number enables SIM swap (porting the user's phone number to attacker's SIM).
- SIM swap enables OTP bypass on banking apps.
- ID document enables credit fraud (cellphone contracts, store accounts).
- Attacker can also impersonate the ratepayer with the municipality.

**Primary control:** Column-Level Encryption (CLE) using Azure Key Vault — **not yet
implemented. This is the mandatory go-live gate.** TDE protects the physical disk but
does not protect against a valid-credential query returning the blob key in plaintext.

**Secondary control:** JWT ownership scope — only `User.id = req.user.id` queries return
`kycDocumentKey`. But this fails if the query scope is wrong (see GAP-1 in blast-radius).

**Why CLE matters even when JWT scoping is correct:** A misconfigured query, a future
endpoint bug, or a compromised admin account can return `kycDocumentKey` even when
ownership scoping is applied correctly elsewhere. CLE ensures that even a correct query
returning the key value returns an encrypted blob key that is useless without Azure Key Vault
access. Without CLE, a single endpoint mistake exposes raw blob keys.

### `EvidenceFile.storageKey` — **SPI** (same risk profile)

An Azure Blob Storage key pointing to an uploaded evidence document. The evidence document
for a bill objection may be a photo of a SA identity document (to prove property ownership).

Risk and controls are identical to `User.kycDocumentKey`. The field name differs but the
data pointed to may be the same: a SA ID document.

---

## PII fields (14 total across 9 models)

| Model | Field | Classification | Rationale |
| --- | --- | --- | --- |
| User | phone | PII | OTP delivery target; not returned in general profile responses |
| User | email | PII | Account recovery; not exposed to third parties |
| User | displayName | PII | User-chosen name; returned only to self |
| User | passwordHash | PII | Derived from user secret; never returned in any response |
| User | deviceToken | PII | Push notification token; enables targeted push if leaked |
| Property | address | PII | Physical address of the rated property |
| Property | ownerName | PII | **Third-party PII** — owner of record may not be the ratepayer |
| Property | accountNumber | PII | Links to billing history; enables account enumeration |
| Property | metadata | **Unknown-PII** | Unaudited JSON blob from municipality export; may contain additional identity fields |
| Account | accountNumber | PII | Municipal billing account identifier |
| Bill | accountNumber | PII | Soft reference to Account; links to billing history |
| EvidenceFile | filename | PII | User-provided filename may contain personal identifiers |
| ObjectionDraft | notes | PII | Free-text notes written by the ratepayer |
| Objection | notes | PII | Final objection text; may contain personal details |

### The `ownerName` problem

`Property.ownerName` is the name of the **owner of record** in the municipality's database.
The ratepayer submitting an objection may be a tenant, not the owner. This makes
`ownerName` third-party PII: it belongs to a person who has not consented to share their
name with EasyRates users.

The blast-radius audit found that `GET /property?accountNumber=` returns `ownerName`
to any authenticated user who knows the account number. This is a POPIA violation:
ratepayer A can retrieve the name of property owner B without B's consent.
See GAP-1 in freeform-blast-radius/overview.md.

### `Property.metadata` — Unknown-PII

This JSON blob is imported from the municipality's CRM export. Its schema has not been
audited against the POPIA inventory. It may contain additional identity fields (valuation
roll number, previous owner history, dispute records). Until audited, it must be treated
as potentially containing PII and should not be returned to clients without filtering.

**Go-live gate action**: audit `Property.metadata` against a live municipality export
before production. Document each sub-field's classification.

---

## Financial fields (7 total)

| Model | Field | Rationale |
| --- | --- | --- |
| Bill | totalAmount | Account-specific; returned only to the account holder |
| BillLineItem | amount | Line-item charge; account-specific |
| BillLineItem | historicalAverage | Consumption comparison baseline; account-specific |
| MunicipalityResponse | adjustedAmount | The municipality's adjusted bill amount |
| AIAmountCalculation | estimatedAmount | AI-estimated fair amount; account-specific |
| AIAmountCalculation | reasoning | AI reasoning may reference account-specific usage patterns |
| AuditEvent | metadata | IP address within metadata = PII; other sub-fields vary |

**Hard-to-classify field rationale (from spot-check):**

- `BillLineItem.historicalAverage` — Financial, not Operational. It is a per-account
  consumption comparison that would reveal usage patterns to a third party. Classified
  Financial because it is account-specific and financially sensitive.

- `AIAmountCalculation.estimatedAmount` — Financial. The AI's estimate of what the bill
  should have been is a financial claim that could be used to dispute the bill in ways
  that benefit the ratepayer — or be used by a third party to infer the ratepayer's
  financial situation.

- `MunicipalityResponse.note` — Operational. Municipality-authored explanatory text.
  Not ratepayer PII; authored by a responsible party employee. Low sensitivity unless
  it contains personal details in free text (edge case, not the norm).

- `AuditEvent.metadata` — Contains an IP address. IP addresses are PII under POPIA (they
  identify a network endpoint used by a person). Remaining metadata fields are operational
  (event type, entity IDs). Masking after 90 days is the accepted pilot posture.

---

## POPIA erasure procedure

When `DELETE /user/account` is called, the erasure must:

1. `User.deletedAt = NOW()` — soft delete (row must remain as FK anchor for Objection).
2. Null: `phone`, `email`, `displayName`, `passwordHash`, `deviceToken`, `kycDocumentKey`.
3. Delete the Azure Blob at `kycDocumentKey` (the actual SA ID document).
4. **Do NOT** null `Objection.notes` — the objection record has a legal retention obligation
   (municipal billing disputes may be referenced in rate appeal proceedings). The notes
   field can be erased if no legal hold applies, but the record itself must be retained.
5. **Do NOT** hard-delete the User row — Objection has a userId FK; hard-deleting breaks
   the objection history chain.

The User row becomes an anonymised anchor: it exists but carries no PII after erasure.

---

## Control gap table

| Gap | Severity | Gate |
| --- | --- | --- |
| CLE not implemented on 14 PII fields across 7 models | Critical | **Go-live gate** — passes all tests silently |
| `Property.metadata` unaudited for PII sub-fields | High | **Go-live gate** |
| `AuditEvent.metadata` IP masking after 90 days | Low | Pilot accepted |
| `RefreshToken` model missing from data-model/user-auth.md | Medium | Before plan/03 |
| `Objection.notes` not nulled on POPIA erasure by default | Medium | Legal hold decision needed |

**The CLE silent-failure pattern:**

CLE absence produces no runtime error. Every test passes. Every API call succeeds. Every
query returns data. The absence of CLE is invisible until a valid-credential attacker or
a misconfigured query returns PII fields that were supposed to be encrypted. This makes
it the most dangerous gap on the list: it actively looks like it is not a gap.

The go-live gate must be enforced at the deployment pipeline level, not just in the plan
tree — a CI gate that checks for `KEY_VAULT_URL` and `JWT_SIGNING_KEY_ID` in the deployment
environment and refuses to deploy without them is the mechanism.

---

## 15-model vs 12-model coverage

The original plan was written for 12 models. The data model has grown to 15:

**Original 12:** User, OTPAttempt, Property, Account, Bill, BillLineItem, Objection,
EvidenceFile, ObjectionDraft, Notification, MunicipalityResponse, AIAmountCalculation

**Added 3:**
- `RefreshToken` — discovered in sessions.md (JWT design); not yet in data-model files.
  Classification: NS (opaque token hash); control: short TTL + rotate-on-use + deletedAt.
- `AuditEvent` — all fields OPS except `metadata.ip` which is PII. Covered above.
- `Municipality` — NS (configuration: name, logo URL, contact email for the municipal
  system of record; no user PII).
