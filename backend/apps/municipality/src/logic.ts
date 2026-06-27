import { timingSafeEqual } from "node:crypto";

/**
 * municipality-service business logic — webhook-local concerns (idempotency
 * replay + shared-secret compare). The objection state machine (which
 * transitions are legal / terminal / no-op) has moved into the swappable
 * `@easyrates/adapters` MunicipalityResponseAdapter; it is re-exported here so
 * the webhook handler and the existing unit tests keep one import surface.
 */

// State machine — single authority lives in the response adapter.
export {
  OBJECTION_STATUSES,
  isTerminal,
  classifyTransition,
} from "@easyrates/adapters";
export type { TransitionDecision } from "@easyrates/adapters";

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
