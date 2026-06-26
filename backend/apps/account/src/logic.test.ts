import { describe, expect, it } from "vitest";
import { maskIdNumberDisplay, maskPhoneDisplay } from "./logic.js";

describe("maskPhoneDisplay", () => {
  it("masks the middle of an E.164 SA number", () => {
    expect(maskPhoneDisplay("+27821234567")).toBe("+27 82 XXX X567");
  });
  it("never leaks the middle digits", () => {
    const masked = maskPhoneDisplay("+27821234567");
    expect(masked).not.toContain("123");
  });
  it("returns empty for a null phone", () => {
    expect(maskPhoneDisplay(null)).toBe("");
  });
  it("passes through a non-matching string unchanged", () => {
    expect(maskPhoneDisplay("12345")).toBe("12345");
  });
});

describe("maskIdNumberDisplay", () => {
  it("emits a fully-masked 13-char placeholder (plaintext never stored)", () => {
    const m = maskIdNumberDisplay("somehash");
    expect(m).toBe("•••••••••••••");
    expect(m).toHaveLength(13);
  });
  it("returns empty when there is no id hash", () => {
    expect(maskIdNumberDisplay(null)).toBe("");
  });
});
