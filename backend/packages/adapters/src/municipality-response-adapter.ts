import type { ObjectionStatus } from "@easyrates/db";

/**
 * MunicipalityResponseAdapter — the INBOUND boundary: a municipal response
 * (delivered by webhook today; a polled `fetchStatus` in some future world) is
 * ingested into the objection state machine here.
 *
 * Path reconciliation: plan 11 T1 sketched this as
 * `easy_rates/backend/shared/adapters/municipality-response-adapter.ts` with a
 * polling `fetchStatus(refNumber)` shape. The status-service was dissolved and
 * ingestion became a PUSH webhook (municipality-service), so there is no polling
 * adapter. The clean, swappable equivalent is this interface: it owns the
 * decision of how an incoming response maps onto the four-value ObjectionStatus
 * state machine. The webhook handler calls through it; a real CRM integration
 * that needs different transition rules swaps the impl.
 *
 * The state machine itself (terminal states + allowed transitions) is the
 * municipality-service.md "State transition rules", moved here verbatim so the
 * one authority is shared by the webhook handler and its tests.
 */

export const OBJECTION_STATUSES: ObjectionStatus[] = [
  "UNDER_REVIEW",
  "MORE_INFO_REQUESTED",
  "UPHELD",
  "REJECTED",
];

const TERMINAL: ReadonlySet<ObjectionStatus> = new Set<ObjectionStatus>([
  "UPHELD",
  "REJECTED",
]);

/** Allowed non-terminal transitions (municipality-service.md State transition rules). */
const ALLOWED: Record<ObjectionStatus, ReadonlySet<ObjectionStatus>> = {
  UNDER_REVIEW: new Set<ObjectionStatus>([
    "MORE_INFO_REQUESTED",
    "UPHELD",
    "REJECTED",
  ]),
  MORE_INFO_REQUESTED: new Set<ObjectionStatus>([
    "UNDER_REVIEW",
    "UPHELD",
    "REJECTED",
  ]),
  UPHELD: new Set<ObjectionStatus>(),
  REJECTED: new Set<ObjectionStatus>(),
};

export function isTerminal(status: ObjectionStatus): boolean {
  return TERMINAL.has(status);
}

export type TransitionDecision =
  | { kind: "apply" } // legal transition → update Objection.status + notify
  | { kind: "terminal" } // 409 conflict — current is terminal, would re-open
  | { kind: "illegal" }; // 422 unprocessable — illegal / no-op transition

/**
 * Classify a requested transition. Every response is still INSERTed for audit
 * upstream — this decides ONLY steps 2 (status update) and 3 (notification).
 *
 *  - current terminal (UPHELD/REJECTED) → `terminal` (409).
 *  - requested ∈ allowed(current)       → `apply`.
 *  - otherwise (no-op or illegal)        → `illegal` (422).
 */
export function classifyTransition(
  current: ObjectionStatus,
  requested: ObjectionStatus,
): TransitionDecision {
  if (isTerminal(current)) return { kind: "terminal" };
  if (ALLOWED[current].has(requested)) return { kind: "apply" };
  return { kind: "illegal" };
}

/** An inbound municipal response, normalised to the four-value status model. */
export interface IncomingMunicipalityResponse {
  refNumber: string;
  status: ObjectionStatus;
  note: string;
  adjustedAmount?: string | null;
}

export interface MunicipalityResponseAdapter {
  /**
   * Classify how an incoming response transitions an objection from its current
   * status. The default impl applies the locked state machine; a real CRM
   * integration with different rules swaps this out.
   */
  classify(
    current: ObjectionStatus,
    incoming: IncomingMunicipalityResponse,
  ): TransitionDecision;
}

/** Default response adapter — the locked four-value state machine. */
export class StateMachineMunicipalityResponseAdapter
  implements MunicipalityResponseAdapter
{
  classify(
    current: ObjectionStatus,
    incoming: IncomingMunicipalityResponse,
  ): TransitionDecision {
    return classifyTransition(current, incoming.status);
  }
}

let defaultResponseAdapter: MunicipalityResponseAdapter =
  new StateMachineMunicipalityResponseAdapter();

/** The process-wide response adapter. Swap via `setMunicipalityResponseAdapter`. */
export function getMunicipalityResponseAdapter(): MunicipalityResponseAdapter {
  return defaultResponseAdapter;
}

/** Override the response adapter (real CRM impl, or a test double). */
export function setMunicipalityResponseAdapter(
  adapter: MunicipalityResponseAdapter,
): void {
  defaultResponseAdapter = adapter;
}
