import type { NextFunction, Request, Response, RequestHandler } from "express";

/**
 * Wrap an async Express handler so rejected promises reach the error middleware
 * instead of hanging the request. Without this, a thrown ApiError inside an
 * `async` handler is an unhandled rejection, not a 4xx/5xx response.
 */
export function asyncHandler(
  handler: (
    req: Request,
    res: Response,
    next: NextFunction,
  ) => Promise<unknown>,
): RequestHandler {
  return (req, res, next) => {
    handler(req, res, next).catch(next);
  };
}
