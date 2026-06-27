import { describe, expect, it } from "vitest";
import {
  classifyTransition,
  decideIdempotency,
  isTerminal,
  secretMatches,
} from "./logic.js";

describe("decideIdempotency — replay vs process", () => {
  it("processes fresh when the key is unseen (null stored)", () => {
    expect(decideIdempotency(null)).toEqual({ kind: "process" });
  });
  it("replays the original payload when the key was seen", () => {
    const stored = JSON.stringify({ refNumber: "ELM-2026-000142", status: "UPHELD", notificationQueued: true });
    expect(decideIdempotency(stored)).toEqual({
      kind: "replay",
      payload: { refNumber: "ELM-2026-000142", status: "UPHELD", notificationQueued: true },
    });
  });
});

describe("classifyTransition — state machine", () => {
  it("UNDER_REVIEW → MORE_INFO_REQUESTED / UPHELD / REJECTED are legal (apply)", () => {
    expect(classifyTransition("UNDER_REVIEW", "MORE_INFO_REQUESTED").kind).toBe("apply");
    expect(classifyTransition("UNDER_REVIEW", "UPHELD").kind).toBe("apply");
    expect(classifyTransition("UNDER_REVIEW", "REJECTED").kind).toBe("apply");
  });

  it("MORE_INFO_REQUESTED → UNDER_REVIEW / UPHELD / REJECTED are legal (apply)", () => {
    expect(classifyTransition("MORE_INFO_REQUESTED", "UNDER_REVIEW").kind).toBe("apply");
    expect(classifyTransition("MORE_INFO_REQUESTED", "UPHELD").kind).toBe("apply");
    expect(classifyTransition("MORE_INFO_REQUESTED", "REJECTED").kind).toBe("apply");
  });

  it("a terminal current (UPHELD/REJECTED) re-open is a 409 conflict (terminal)", () => {
    expect(classifyTransition("UPHELD", "UNDER_REVIEW").kind).toBe("terminal");
    expect(classifyTransition("REJECTED", "UPHELD").kind).toBe("terminal");
    expect(classifyTransition("UPHELD", "REJECTED").kind).toBe("terminal");
  });

  it("a no-op (same non-terminal status) is a 422 illegal", () => {
    expect(classifyTransition("UNDER_REVIEW", "UNDER_REVIEW").kind).toBe("illegal");
    expect(classifyTransition("MORE_INFO_REQUESTED", "MORE_INFO_REQUESTED").kind).toBe("illegal");
  });

  it("isTerminal flags only UPHELD and REJECTED", () => {
    expect(isTerminal("UPHELD")).toBe(true);
    expect(isTerminal("REJECTED")).toBe(true);
    expect(isTerminal("UNDER_REVIEW")).toBe(false);
    expect(isTerminal("MORE_INFO_REQUESTED")).toBe(false);
  });
});

describe("secretMatches — constant-time shared-secret compare", () => {
  it("matches the exact secret", () => {
    expect(secretMatches("s3cr3t", "s3cr3t")).toBe(true);
  });
  it("rejects a wrong secret of the same length", () => {
    expect(secretMatches("s3cr3X", "s3cr3t")).toBe(false);
  });
  it("rejects a length mismatch", () => {
    expect(secretMatches("short", "longer-secret")).toBe(false);
  });
  it("rejects an undefined / empty provided secret", () => {
    expect(secretMatches(undefined, "s3cr3t")).toBe(false);
    expect(secretMatches("", "s3cr3t")).toBe(false);
  });
});
