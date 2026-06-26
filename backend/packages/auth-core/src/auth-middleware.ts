import type { NextFunction, Request, Response } from "express";
import { ApiError } from "@easyrates/http";
import type { TokenService } from "./tokens.js";

/** Express request augmented with the authenticated userId (conventions §6). */
export interface AuthedRequest extends Request {
  userId?: string;
}

/**
 * Shared RS256 bearer-auth middleware (conventions §6). Extracts
 * `Authorization: Bearer <token>`, verifies it (RS256, iss/aud/exp) via the
 * shared TokenService, and attaches `req.userId`. Any failure →
 * `401 unauthenticated`.
 *
 * Promoted here (from apps/auth) so property/bill/account reuse ONE
 * implementation instead of duplicating it three times.
 */
export function requireAuth(tokens: TokenService) {
  return (req: AuthedRequest, _res: Response, next: NextFunction): void => {
    const header = req.header("authorization") ?? "";
    const match = /^Bearer (.+)$/.exec(header);
    if (!match) {
      next(ApiError.unauthenticated("Missing bearer token."));
      return;
    }
    try {
      const claims = tokens.verifyAccessToken(match[1]!);
      req.userId = claims.sub;
      next();
    } catch (e) {
      next(e);
    }
  };
}
