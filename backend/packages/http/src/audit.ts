import { Prisma, prisma, type AuditEventType } from "@easyrates/db";

/**
 * Best-effort AuditEvent emission (data-model DECISION-B, manual AuditEvent).
 *
 * The `AuditEvent` model is the POPIA append-only audit trail (see
 * `system-design/docs/data-model/user-auth.md`). The set of legal `event`
 * values is the SEALED `AuditEventType` enum — this helper is typed to it so a
 * non-enum event name is a compile error, not a runtime surprise.
 *
 * Contract:
 *  - NEVER throws. An audit write must never break the request it observes — a
 *    failed INSERT is swallowed and logged, the caller proceeds.
 *  - NEVER persists secrets/PII. `userId` is the safe handle; never pass a raw
 *    phone or idNumber. `metadata` is for non-sensitive context (masked phone,
 *    a status, a ref number). Callers are responsible for masking before they
 *    hand a value to `writeAudit`.
 *
 * `entityId`/`entityType` index the audited subject (e.g. an objection id), and
 * are stored in the model's dedicated columns; everything else rides in
 * `metadata` (Json?).
 */
export interface WriteAuditArgs {
  /** The audited event. Constrained to the sealed AuditEventType enum. */
  event: AuditEventType;
  /** Acting user id, when known. Pre-auth events (e.g. LOGIN_FAILED) have none. */
  userId?: string | null;
  /** Subject entity id (objection id, etc.). Stored in AuditEvent.entityId. */
  entityId?: string | null;
  /** Subject entity type label. Stored in AuditEvent.entityType. */
  entityType?: string | null;
  /** Request source IP, when available. Folded into metadata (never a column). */
  ip?: string | null;
  /** Non-sensitive structured context. NO raw phone/idNumber/secrets. */
  metadata?: Record<string, unknown>;
}

/**
 * Insert one AuditEvent row. Best-effort: resolves even if the INSERT fails.
 * Returns the new row id on success, or `null` if the write was swallowed.
 */
export async function writeAudit(args: WriteAuditArgs): Promise<string | null> {
  try {
    const metadata: Record<string, unknown> = { ...(args.metadata ?? {}) };
    if (args.ip != null && metadata.ip === undefined) {
      metadata.ip = args.ip;
    }
    const row = await prisma.auditEvent.create({
      data: {
        event: args.event,
        userId: args.userId ?? null,
        entityId: args.entityId ?? null,
        entityType: args.entityType ?? null,
        metadata:
          Object.keys(metadata).length > 0
            ? (metadata as Prisma.InputJsonValue)
            : undefined,
      },
      select: { id: true },
    });
    return row.id;
  } catch (e) {
    // Audit is observational — it must never break the observed request.
    console.warn("[audit] writeAudit failed (non-fatal):", e);
    return null;
  }
}
