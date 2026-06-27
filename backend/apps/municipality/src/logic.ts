import { timingSafeEqual } from "node:crypto";
import type { ObjectionStatus } from "@easyrates/db";

/**
 * municipality-service business logic — pure state machine + secret comparison.
 * The DB writes, Redis idempotency, and HTTP live in app.ts; the decisions worth
 * testing (which transitions are legal, terminal, or no-ops) live here.
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

/**
 * Idempotency replay decision. Given the stored value for an idempotencyKey
 * (the original response JSON, or null if unseen), decide whether to replay the
 * original result or process the request fresh. Pure so the replay contract is
 * unit-testable without Redis.
 */
export function decideIdempotency(
  storedResponse: string | null,
):
  | { kind: "replay"; payload: unknown }
  | { kind: "process" } {
  if (storedResponse == null) return { kind: "process" };
  return { kind: "replay", payload: JSON.parse(storedResponse) };
}

/**
 * Constant-time shared-secret comparison. Length-mismatch returns false without
 * leaking timing (compare against a same-length buffer first).
 */
export function secretMatches(
  provided: string | undefined,
  expected: string,
): boolean {
  if (!provided) return false;
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  if (a.length !== b.length) {
    // Still do a constant-time compare against `a` to avoid an early-out timing
    // signal on length, then return false.
    timingSafeEqual(a, a);
    return false;
  }
  return timingSafeEqual(a, b);
}
