# Coverage Manifest — security-analysis-2026-06-20

Every checkbox below traces to a unit in the captured markdowns. When
`/curriculum` builds plans from this folder, every manifest item should
appear in at least one plan task.

Note: `/socratic` and `/unpack` outputs from this session were compacted and
cannot be captured. The items below cover only the content in context:
the POPIA classification reasoning and the blast-radius audit methodology.

---

## freeform: POPIA classification

- [ ] SPI/PII/FIN/OPS/NS framework and tier definitions — `freeform-popia-classification/overview.md` (Classification framework)
- [ ] POPIA §26 SPI definition: SA identity documents as biometric-adjacent — same file
- [ ] Breach notification: ≤72h, Information Regulator + data subjects, R10M penalty — same file
- [ ] `User.kycDocumentKey` as SPI: blob key → SA ID document → SIM swap / credit fraud risk — same file (Two SPI fields)
- [ ] `EvidenceFile.storageKey` as SPI: same risk profile as kycDocumentKey — same file
- [ ] CLE silent-failure pattern: no runtime error, all tests pass, go-live gate — same file
- [ ] `Property.ownerName` as third-party PII — same file (PII fields)
- [ ] `Property.metadata` as Unknown-PII pending audit — same file
- [ ] Hard-to-classify rationale: `historicalAverage` → Financial — same file (Financial fields)
- [ ] Hard-to-classify rationale: `AIAmountCalculation.estimatedAmount` → Financial — same file
- [ ] Hard-to-classify rationale: `MunicipalityResponse.note` → Operational — same file
- [ ] Hard-to-classify rationale: `AuditEvent.metadata` contains IP (PII) — same file
- [ ] POPIA erasure procedure: soft delete + null fields + blob delete — same file (Erasure procedure)
- [ ] Erasure constraint: Objection.notes not nulled (legal retention obligation) — same file
- [ ] Erasure constraint: User row not hard-deleted (FK anchor for Objection) — same file
- [ ] Control gap table: 5 gaps, severity, gate — same file (Control gap table)
- [ ] 15-model vs 12-model coverage: AuditEvent, Municipality, RefreshToken additions — same file

---

## freeform: Blast-radius audit

- [ ] Pattern 1 — Direct userId: User, Notification, ObjectionDraft, Account — `freeform-blast-radius/overview.md` (Pattern 1)
- [ ] Pattern 2 — Single-query ownership check: `findFirst({ where: { id, userId } })` — same file (Pattern 2)
- [ ] Pattern 2 WRONG vs CORRECT: two-step fetch-then-check leaks existence via 403 — same file
- [ ] 404-not-403 rule: attacker cannot distinguish non-existence from forbidden — same file
- [ ] Pattern 3 — Bill chain traversal: two queries, soft accountNumber reference — same file (Pattern 3)
- [ ] Why no Prisma relation on Bill: accountNumber is plain String, not FK — same file
- [ ] Pattern 4 — Property ownership chain: User → Account.userId + Account.accountNumber = Property.accountNumber — same file (Pattern 4)
- [ ] `shared/authz.ts`: 4 utility function signatures (assertOwnsProperty, assertOwnsBill, assertOwnsObjection, assertOwnsObjectionByRef) — same file (Required utilities)
- [ ] Import rule A8: every handler imports from shared/authz.ts, never re-implements — same file
- [ ] Blast-radius verdict table: 12 rows, resources and accessibility — same file (Verdict table)
- [ ] GAP-1 (HIGH): GET /property?accountNumber= returns ownerName without ownership check — same file (GAP-1)
- [ ] GAP-1 Fix A: remove `owner` from pre-link response — same file
- [ ] GAP-1 Fix B: soft gate — owner only if accountNumber matches linked Account — same file
- [ ] GAP-2 (LOW): GET /property/search?q= returns address + accountNumber — same file (GAP-2)
- [ ] GAP-3: GET /property/:id/pdf undocumented; assertOwnsProperty required — same file (GAP-3)
- [ ] GAP-4: 4 undocumented status-service endpoints with required ownership assertions — same file (GAP-4)
- [ ] Endpoint naming discrepancy: /objection/:id/documents vs /objections/:id/evidence — same file (Naming discrepancy)
- [ ] A1–A8 action table before plan/09 closes — same file (Action items)
