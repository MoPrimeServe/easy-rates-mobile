/**
 * Gateway routing table (api/conventions.md §1).
 *
 * The gateway is the single origin behind which all 8 service apps sit. The
 * Flutter app talks to ONE base URL — `http://<host>:8080/api/v1` — and the
 * gateway dispatches each request to the correct service by the FIRST path
 * segment after the `/api/v1` prefix.
 *
 * Crucial invariant: the services serve their canonical paths WITHOUT the
 * `/api/v1` prefix (e.g. auth-service serves `POST /auth/login`, bill-service
 * serves `GET /bills`). The gateway therefore STRIPS `/api/v1` from the path
 * before forwarding — `pathRewrite` removes the leading `^/api/v1`.
 *
 * Each service's base URL comes from env (AUTH_URL, OTP_URL, …) defaulting to
 * `http://localhost:<port>` matching that service's `server.ts` default PORT.
 */

import { env } from "@easyrates/config";

export interface ServiceRoute {
  /** Service identifier (also used for the env URL key and /health label). */
  readonly name: string;
  /**
   * URL path segments under `/api/v1` that belong to this service. Matching is
   * done on the first segment after `/api/v1/` — e.g. `bills` matches both
   * `/api/v1/bills` and `/api/v1/bills/:id/lines`.
   */
  readonly segments: readonly string[];
  /** Downstream base origin, e.g. `http://localhost:3001`. */
  readonly target: string;
}

/**
 * The route table. Order is irrelevant — dispatch is by exact first-segment
 * lookup, never by prefix-overlap precedence. Defaults match each service's
 * `server.ts` fallback PORT:
 *   auth 3001 · otp 3002 · property 3003 · bill 3005 · objection 3006 (dev
 *   override; see note) · notification 3007 · municipality 3008 · account 3009.
 *
 * NOTE on bill/objection: both `server.ts` files default to 3005. They cannot
 * co-exist on one port, so in local dev objection is run on 3006 (set via
 * OBJECTION_PORT in .env) and the gateway's OBJECTION_URL default points at
 * 3006 to match. The podman-compose mapping is independent (each container
 * listens on 3000 internally).
 */
export const ROUTES: readonly ServiceRoute[] = [
  {
    name: "auth",
    // `.well-known/jwks.json` is the auth-service JWKS endpoint (no /auth prefix
    // on the service side); it is special-cased onto the auth target below.
    segments: ["auth", ".well-known"],
    target: env.AUTH_URL,
  },
  { name: "otp", segments: ["otp"], target: env.OTP_URL },
  { name: "property", segments: ["property"], target: env.PROPERTY_URL },
  { name: "bill", segments: ["bills", "bill"], target: env.BILL_URL },
  { name: "account", segments: ["account"], target: env.ACCOUNT_URL },
  { name: "objection", segments: ["objections"], target: env.OBJECTION_URL },
  {
    name: "notification",
    segments: ["notifications"],
    target: env.NOTIFICATION_URL,
  },
  {
    name: "municipality",
    segments: ["municipality"],
    target: env.MUNICIPALITY_URL,
  },
] as const;

/** All `/api/v1` paths share this prefix; the gateway strips it on forward. */
export const API_PREFIX = "/api/v1";

/**
 * Build a `segment → ServiceRoute` lookup map for O(1) dispatch. Each route's
 * `segments` all point at the same service.
 */
export function buildSegmentMap(
  routes: readonly ServiceRoute[] = ROUTES,
): ReadonlyMap<string, ServiceRoute> {
  const map = new Map<string, ServiceRoute>();
  for (const route of routes) {
    for (const segment of route.segments) {
      map.set(segment, route);
    }
  }
  return map;
}

/** Extract the first path segment after `/api/v1/` (`""` if none). */
export function firstSegment(path: string): string {
  // path is everything after API_PREFIX, e.g. "/auth/login" → "auth".
  const trimmed = path.replace(/^\/+/, "");
  const slash = trimmed.indexOf("/");
  const seg = slash === -1 ? trimmed : trimmed.slice(0, slash);
  // Drop any querystring clinging to a single-segment path (`bills?page=1`).
  return seg.split("?")[0] ?? "";
}
