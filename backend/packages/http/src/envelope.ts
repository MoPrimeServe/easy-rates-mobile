/**
 * The `{ data, error }` response envelope (api/conventions.md §2).
 *
 * Invariants (conventions §2):
 *  - `data` is never absent — it is `null` on error.
 *  - `error` is never absent — it is `null` on success.
 *  - Exactly one of `data` / `error` is non-null (biconditional).
 *  - Empty successes return `{}`, never `null`, never a bodiless 204.
 */

export interface ApiErrorBody {
  /** snake_case, machine-readable; the client switches on THIS, not HTTP status. */
  code: string;
  /** human-readable; safe to render in the Flutter UI. */
  message: string;
  /** optional; always an object (never an array); may be `{}`. */
  details?: Record<string, unknown>;
}

export interface ApiResponse<T> {
  data: T | null;
  error: ApiErrorBody | null;
}

/** Build a success envelope. Pass `{}` for empty successes (logout/ack/delete). */
export function ok<T>(data: T): ApiResponse<T> {
  return { data, error: null };
}

/** Build an error envelope. `details` always serialises as an object. */
export function fail(
  code: string,
  message: string,
  details: Record<string, unknown> = {},
): ApiResponse<never> {
  return { data: null, error: { code, message, details } };
}
