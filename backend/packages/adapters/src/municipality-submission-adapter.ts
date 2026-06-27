import { prisma } from "@easyrates/db";

/**
 * MunicipalitySubmissionAdapter — the OUTBOUND boundary to the municipal CRM.
 *
 * Path reconciliation: the original plan (09 T2) sketched this as a single file
 * `easy_rates/backend/shared/adapters/municipality-submission-adapter.ts`. The
 * monorepo layout has no `shared/` tree — the equivalent clean, swappable
 * interface lives here in `@easyrates/adapters` and is wired into the
 * objection-submit worker. The intent (one replaceable function/object behind a
 * named interface, so the real ELM system drops in later) is satisfied.
 *
 * When the municipality exposes a real submission API, implement this interface
 * against it (HTTP call → their case-ref) and swap it in at the worker's
 * factory. The default impl below is the current behaviour: it mints the ELM
 * reference locally (no external system yet).
 */

export interface SubmissionRequest {
  /** The Objection.id being submitted. */
  objectionId: string;
  /** The owning user id (for the adapter's audit/context, never persisted as PII). */
  userId: string;
}

export interface SubmissionResult {
  /** The municipal case reference assigned to this objection (ELM-2026-NNNNNN). */
  refNumber: string;
}

export interface MunicipalitySubmissionAdapter {
  /**
   * Submit an objection to the municipality and return the assigned reference.
   * Implementations must be idempotent at the ref level where possible.
   */
  submit(req: SubmissionRequest): Promise<SubmissionResult>;
}

/**
 * Generate the next ELM-YYYY-NNNNNN reference. NNNNNN is the count of objections
 * already carrying a refNumber + 1, zero-padded to 6 digits. Collisions are
 * caught by the Objection.refNumber @unique constraint and retried upstream by
 * the worker's `attempts`. (Moved verbatim from the objection-submit queue.)
 */
export async function nextElmRefNumber(): Promise<string> {
  const year = new Date().getUTCFullYear();
  const count = await prisma.objection.count({
    where: { refNumber: { not: null } },
  });
  const seq = String(count + 1).padStart(6, "0");
  return `ELM-${year}-${seq}`;
}

/**
 * Default (stub) submission adapter — the MVP behaviour: no real municipal CRM
 * exists, so "submitting" means minting the ELM reference locally. This is the
 * seam the real adapter replaces.
 */
export class StubMunicipalitySubmissionAdapter
  implements MunicipalitySubmissionAdapter
{
  async submit(_req: SubmissionRequest): Promise<SubmissionResult> {
    const refNumber = await nextElmRefNumber();
    return { refNumber };
  }
}

let defaultSubmissionAdapter: MunicipalitySubmissionAdapter =
  new StubMunicipalitySubmissionAdapter();

/** The process-wide submission adapter. Swap via `setMunicipalitySubmissionAdapter`. */
export function getMunicipalitySubmissionAdapter(): MunicipalitySubmissionAdapter {
  return defaultSubmissionAdapter;
}

/** Override the submission adapter (real CRM impl, or a test double). */
export function setMunicipalitySubmissionAdapter(
  adapter: MunicipalitySubmissionAdapter,
): void {
  defaultSubmissionAdapter = adapter;
}
