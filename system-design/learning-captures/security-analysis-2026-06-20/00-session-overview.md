# Session Overview — security-analysis-2026-06-20
Captured: 2026-06-20

## What was studied

A multi-session security design thread for EasyRates. The session produced the full
POPIA field inventory (all 15 Prisma models classified), a blast-radius audit of all
37 endpoints (verifying user-scoping and flagging cross-user data leaks), and a
sync of the plan/07 security design tree.

The core intellectual work was two-pronged: (1) classifying every database field
under POPIA and identifying which constitutes Special Personal Information with
stricter obligations; (2) auditing every API endpoint against the four Prisma
ownership-scoping patterns and finding two property-service gaps where a valid
JWT could retrieve another user's PII.

## Sequence of skills

1. `/socratic` on "POPIA breach notification obligations" — **COMPACTED**: output not in context
2. `/unpack` on "POPIA — personal information vs special personal information" — **COMPACTED**: output not in context
3. freeform: POPIA field inventory analysis (all 15 models) → `docs/security/popia-inventory.md`
4. freeform: blast-radius endpoint audit (37 endpoints, 4 scoping patterns) → `docs/security/authorization.md`
5. `/sync-plan-tree` on `plans/07-security-design.md` → 10 plan files updated

## Cross-references

The POPIA classification work (freeform-popia-classification) directly determined
the severity of the blast-radius gap: GAP-1 matters because `Property.ownerName`
is PII belonging to a third party, not the requesting user. Without the POPIA
classification establishing `ownerName` as PII, GAP-1 might have been rated Low.

The 404-not-403 rule in the blast-radius audit (freeform-blast-radius) connects
to the CLE control gap in the POPIA inventory — both are "passes tests silently"
security failures: 403 leaks resource existence the same way that absent CLE
passes all tests while leaving PII unencrypted.

## Open ends

- `/socratic` compile artifact on POPIA breach triggers: compacted, not captured.
- `/unpack` five-part structure on POPIA obligations: compacted, not captured.
- plan/02 VERIFY task remains ⚠️ pending `api/conventions.md` (api-contracts sub-scope not started).
- A1–A8 action items (see freeform-blast-radius/overview.md) are tracked in `docs/security/authorization.md` but not yet in the plan tree — candidate for `/curriculum`.
