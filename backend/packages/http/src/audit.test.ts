import { afterEach, describe, expect, it, vi } from "vitest";

// Mock the Prisma singleton so writeAudit can be unit-tested without a DB.
const create = vi.fn();
vi.mock("@easyrates/db", () => ({
  prisma: { auditEvent: { create: (...args: unknown[]) => create(...args) } },
  // writeAudit casts metadata to Prisma.InputJsonValue — provide a stub namespace.
  Prisma: {},
}));

const { writeAudit } = await import("./audit.js");

describe("writeAudit", () => {
  afterEach(() => {
    create.mockReset();
    vi.restoreAllMocks();
  });

  it("inserts an AuditEvent row and returns its id", async () => {
    create.mockResolvedValue({ id: "audit_1" });
    const id = await writeAudit({
      event: "LOGIN_SUCCESS",
      userId: "usr_1",
      entityId: "usr_1",
      entityType: "User",
      ip: "1.2.3.4",
      metadata: { foo: "bar" },
    });
    expect(id).toBe("audit_1");
    expect(create).toHaveBeenCalledTimes(1);
    const arg = create.mock.calls[0]![0] as {
      data: Record<string, unknown>;
      select: unknown;
    };
    expect(arg.data.event).toBe("LOGIN_SUCCESS");
    expect(arg.data.userId).toBe("usr_1");
    expect(arg.data.entityId).toBe("usr_1");
    expect(arg.data.entityType).toBe("User");
    // ip folds into metadata (not a column).
    expect(arg.data.metadata).toEqual({ foo: "bar", ip: "1.2.3.4" });
    expect(arg.select).toEqual({ id: true });
  });

  it("defaults nullable fields to null and omits empty metadata", async () => {
    create.mockResolvedValue({ id: "audit_2" });
    await writeAudit({ event: "LOGIN_FAILED" });
    const arg = create.mock.calls[0]![0] as { data: Record<string, unknown> };
    expect(arg.data.userId).toBeNull();
    expect(arg.data.entityId).toBeNull();
    expect(arg.data.entityType).toBeNull();
    expect(arg.data.metadata).toBeUndefined();
  });

  it("is best-effort: swallows a DB error and returns null (never throws)", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    create.mockRejectedValue(new Error("db down"));
    const id = await writeAudit({ event: "OBJECTION_SUBMITTED", userId: "usr_1" });
    expect(id).toBeNull();
  });
});
