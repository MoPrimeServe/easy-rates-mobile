import type { Request, Response, RequestHandler } from "express";
import { prisma } from "@easyrates/db";

type ComponentStatus = "connected" | "disconnected" | "skipped";

export interface HealthReport {
  status: "ok" | "degraded";
  service: string;
  db: ComponentStatus;
  queue: ComponentStatus;
}

/**
 * Reusable `GET /health` handler. Reports `{ status, service, db, queue }`.
 *
 *  - db: `SELECT 1` via `prisma.$queryRaw`. A failure means 503.
 *  - queue: optional. If a `pingQueue` probe is supplied it is awaited;
 *    otherwise the queue is reported `skipped` (Redis is optional locally and
 *    must not fail the health check when absent — conventions/podman skeleton).
 *
 * Returns HTTP 200 only when the DB is reachable; 503 otherwise, naming the
 * failing component in the body.
 */
export function makeHealthHandler(options: {
  serviceName: string;
  pingQueue?: () => Promise<boolean>;
}): RequestHandler {
  const { serviceName, pingQueue } = options;

  return async (_req: Request, res: Response): Promise<void> => {
    let db: ComponentStatus = "disconnected";
    try {
      await prisma.$queryRaw`SELECT 1`;
      db = "connected";
    } catch {
      db = "disconnected";
    }

    let queue: ComponentStatus = "skipped";
    if (pingQueue) {
      try {
        queue = (await pingQueue()) ? "connected" : "disconnected";
      } catch {
        queue = "disconnected";
      }
    }

    // DB is the hard dependency. A skipped queue does not degrade health;
    // an explicitly disconnected queue does.
    const healthy = db === "connected" && queue !== "disconnected";
    const report: HealthReport = {
      status: healthy ? "ok" : "degraded",
      service: serviceName,
      db,
      queue,
    };
    res.status(healthy ? 200 : 503).json(report);
  };
}
