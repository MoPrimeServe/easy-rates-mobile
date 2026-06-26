import type { NextFunction, Request, Response } from "express";
import { ApiError } from "./api-error.js";
import { fail } from "./envelope.js";

/**
 * Global error middleware. Mount LAST (after all routes). Maps:
 *  - ApiError       → its code / httpStatus / details (conventions §3)
 *  - anything else  → 500 internal_server_error (never leaks a stack trace).
 *
 * Express identifies error middleware by its 4-arg signature; `_next` must stay.
 */
export function errorMiddleware(
  err: unknown,
  _req: Request,
  res: Response,
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _next: NextFunction,
): void {
  if (err instanceof ApiError) {
    if (err.code === "rate_limit_exceeded") {
      const retry = Number(err.details.retryAfterSeconds ?? 0);
      if (retry > 0) res.setHeader("Retry-After", String(retry));
    }
    res
      .status(err.httpStatus)
      .json(fail(err.code, err.message, err.details));
    return;
  }

  // Unknown error — log server-side, return a safe generic envelope.
  console.error("[error] unhandled:", err);
  res
    .status(500)
    .json(fail("internal_server_error", "An unexpected error occurred."));
}

/** 404 fallthrough for unmatched routes. Mount just before errorMiddleware. */
export function notFoundMiddleware(_req: Request, res: Response): void {
  res
    .status(404)
    .json(fail("not_found", "Resource not found."));
}
