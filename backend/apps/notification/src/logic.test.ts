import { describe, expect, it } from "vitest";
import type { Notification } from "@easyrates/db";
import { countUnread, inboxWhere, isRead, toInboxItem } from "./logic.js";

const notif = (over: Partial<Notification> = {}): Notification =>
  ({
    id: "n1",
    userId: "u1",
    objectionId: null,
    type: "OBJECTION_STATUS",
    channel: "PUSH",
    status: "SENT",
    sentAt: new Date("2026-06-15T10:30:00.000Z"),
    readAt: null,
    ...over,
  }) as Notification;

describe("inboxWhere — unreadOnly filter", () => {
  it("scopes to userId only when unreadOnly is false", () => {
    expect(inboxWhere("u1", false)).toEqual({ userId: "u1" });
  });
  it("adds readAt: null when unreadOnly is true", () => {
    expect(inboxWhere("u1", true)).toEqual({ userId: "u1", readAt: null });
  });
});

describe("countUnread — read-all updatedCount semantics", () => {
  it("counts only rows with readAt == null", () => {
    expect(
      countUnread([
        notif({ readAt: null }),
        notif({ readAt: new Date() }),
        notif({ readAt: null }),
      ]),
    ).toBe(2);
  });
  it("returns 0 when every row is already read", () => {
    expect(
      countUnread([notif({ readAt: new Date() }), notif({ readAt: new Date() })]),
    ).toBe(0);
  });
  it("returns 0 for an empty inbox", () => {
    expect(countUnread([])).toBe(0);
  });
});

describe("isRead derives read from readAt", () => {
  it("false when readAt is null", () => {
    expect(isRead(notif({ readAt: null }))).toBe(false);
  });
  it("true when readAt is set", () => {
    expect(isRead(notif({ readAt: new Date() }))).toBe(true);
  });
});

describe("toInboxItem", () => {
  it("composes title/preview by type and surfaces objectionRef + read", () => {
    const item = toInboxItem(notif({ type: "OBJECTION_RECEIVED" }), "ELM-2026-000123");
    expect(item.objectionRef).toBe("ELM-2026-000123");
    expect(item.read).toBe(false);
    expect(item.title).toBe("Objection received");
    expect(item.sentAt).toBe("2026-06-15T10:30:00.000Z");
  });
  it("objectionRef is null for bill-lifecycle types", () => {
    expect(toInboxItem(notif({ type: "BILL_ISSUED" }), null).objectionRef).toBeNull();
  });
});
