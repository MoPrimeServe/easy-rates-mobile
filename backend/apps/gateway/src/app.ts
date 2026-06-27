import express, { type Express, type Request, type Response } from "express";
import {
  createProxyMiddleware,
  type Options,
} from "http-proxy-middleware";
import { fail } from "@easyrates/http";
import {
  API_PREFIX,
  buildSegmentMap,
  firstSegment,
  ROUTES,
  type ServiceRoute,
} from "./routes.js";

/**
 * API gateway (api/conventions.md §1) — a thin reverse proxy so the Flutter app
 * talks to ONE origin under `/api/v1` and the gateway dispatches to the 8
 * service apps by first path segment, STRIPPING the `/api/v1` prefix before
 * forwarding (services serve canonical paths without the prefix).
 *
 * Design notes:
 *  - NO body parser runs ahead of the proxy. http-proxy-middleware streams the
 *    raw request (method, body, headers — incl. Authorization and
 *    X-Municipal-Webhook-Secret) straight through, and pipes the downstream
 *    response (status + `{data,error}` envelope) back unchanged.
 *  - A downstream that is unreachable (ECONNREFUSED/timeout) is caught and
 *    answered with a clean 502 in the same envelope shape, never a raw socket
 *    error.
 */

const FETCH_HEALTH_TIMEOUT_MS = 1500;

/** Build the per-service proxy with `/api/v1` stripped on forward. */
function makeServiceProxy(route: ServiceRoute) {
  const options: Options = {
    target: route.target,
    changeOrigin: true,
    // The Flutter app addresses `/api/v1/auth/login`; the auth-service serves
    // `/auth/login`. Strip the shared prefix so the canonical path is forwarded.
    pathRewrite: { [`^${API_PREFIX}`]: "" },
    // Preserve the original method/body/headers; stream them through verbatim.
    on: {
      error: (err: Error, _req, res) => {
        // `res` is a ServerResponse here (not always an Express Response).
        const response = res as Response;
        if (response.headersSent) {
          response.end();
          return;
        }
        response.statusCode = 502;
        response.setHeader("Content-Type", "application/json");
        response.end(
          JSON.stringify(
            fail(
              "service_unavailable",
              `The ${route.name} service is currently unavailable. Please try again shortly.`,
              { service: route.name, reason: err.message },
            ),
          ),
        );
      },
    },
  };
  return createProxyMiddleware(options);
}

export function createGatewayApp(): Express {
  const app = express();
  const segmentMap = buildSegmentMap(ROUTES);

  // One proxy middleware instance per service, reused across requests.
  const proxies = new Map<string, ReturnType<typeof makeServiceProxy>>();
  for (const route of ROUTES) {
    proxies.set(route.name, makeServiceProxy(route));
  }

  // ---- GET /health  [gateway] ----------------------------------------------
  // Aggregates downstream /health best-effort. The gateway itself is "ok" as
  // long as it is serving; each service's reachability is reported per-service.
  app.get("/health", async (_req: Request, res: Response): Promise<void> => {
    const services = await Promise.all(
      ROUTES.map(async (route) => {
        const url = `${route.target}${API_PREFIX}/health`;
        // Services mount /health WITHOUT the prefix, so probe the stripped path.
        const probeUrl = `${route.target}/health`;
        const controller = new AbortController();
        const timer = setTimeout(
          () => controller.abort(),
          FETCH_HEALTH_TIMEOUT_MS,
        );
        try {
          const r = await fetch(probeUrl, { signal: controller.signal });
          const body = (await r.json().catch(() => null)) as
            | { status?: string }
            | null;
          return {
            name: route.name,
            reachable: r.ok,
            status: body?.status ?? (r.ok ? "ok" : "degraded"),
          };
        } catch {
          return { name: route.name, reachable: false, status: "unreachable" };
        } finally {
          clearTimeout(timer);
          void url;
        }
      }),
    );

    const allUp = services.every((s) => s.reachable);
    res.status(200).json({
      status: allUp ? "ok" : "degraded",
      service: "gateway",
      services,
    });
  });

  // ---- Dispatch /api/v1/<segment>/* to the owning service ------------------
  // Mounted at root (NOT under API_PREFIX) so req.url keeps the `/api/v1` prefix
  // intact — the per-service `pathRewrite` is what strips it on forward. This
  // keeps the strip in ONE place and avoids Express's mount-path stripping.
  app.use((req: Request, res: Response, next): void => {
    if (!req.url.startsWith(`${API_PREFIX}/`) && req.url !== API_PREFIX) {
      res
        .status(404)
        .json(
          fail("not_found", "All EasyRates API routes live under /api/v1.", {}),
        );
      return;
    }
    const afterPrefix = req.url.slice(API_PREFIX.length); // e.g. "/auth/login"
    const segment = firstSegment(afterPrefix);
    const route = segmentMap.get(segment);
    if (!route) {
      res
        .status(404)
        .json(
          fail(
            "not_found",
            `No service is registered for /api/v1/${segment}.`,
            { segment },
          ),
        );
      return;
    }
    const proxy = proxies.get(route.name);
    if (!proxy) {
      next();
      return;
    }
    proxy(req, res, next);
  });

  return app;
}
