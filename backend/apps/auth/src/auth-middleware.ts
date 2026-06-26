import type { NextFunction, Request, Response } from "express";
import { ApiError } from "@easyrates/http";
import type { TokenService } from "@easyrates/auth-core";

/** Express request augmented with the authenticated userId. */
export interface AuthedRequest extends Request {
  userId?: string;
}

/**
 * JWT access-token middleware. Extracts `Authorization: Bearer <token>`,
 * verifies it (RS256, iss/aud/exp), and attaches `req.userId`. Any failure →
 * 401 unauthenticated (conventions §3, §6).
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
