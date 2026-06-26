import { describe, expect, it } from "vitest";
import type { Property } from "@easyrates/db";
import { passesIdentityGate, toDetail, toSummary, ward } from "./mappers.js";

const baseProperty = (over: Partial<Property> = {}): Property =>
  ({
    id: "clr8x2k9a0001",
    municipalityId: "muni1",
    accountNumber: "10045821",
    address: "123 Main Street, Vereeniging",
    erfNumber: "ERF/001/VRG",
    ownerName: "Jane Doe",
    holderIdNumberHashes: ["hashA", "hashB"],
    city: "Emfuleni",
    metadata: {
      ward: "Ward 12",
      extentSqm: 495,
      municipalValue: "1850000.00",
      dataAsOf: "2026-06-15T02:00:00.000Z",
    },
    ...over,
  }) as Property;

describe("identity gate (ADR-003)", () => {
  it("passes when the user hash is among the holder hashes", () => {
    expect(passesIdentityGate("hashA", ["hashA", "hashB"])).toBe(true);
  });

  it("fails when the user hash is absent", () => {
    expect(passesIdentityGate("hashZ", ["hashA", "hashB"])).toBe(false);
  });

  it("fails when the user has no id hash (null)", () => {
    expect(passesIdentityGate(null, ["hashA"])).toBe(false);
  });

  it("fails against an empty holder set", () => {
    expect(passesIdentityGate("hashA", [])).toBe(false);
  });
});

describe("toSummary", () => {
  it("projects the summary fields incl. ward from metadata", () => {
    expect(toSummary(baseProperty())).toEqual({
      id: "clr8x2k9a0001",
      accountNumber: "10045821",
      ownerName: "Jane Doe",
      address: "123 Main Street, Vereeniging",
      erfNumber: "ERF/001/VRG",
      ward: "Ward 12",
    });
  });

  it("preserves a null ownerName / erfNumber", () => {
    const s = toSummary(baseProperty({ ownerName: null, erfNumber: null }));
    expect(s.ownerName).toBeNull();
    expect(s.erfNumber).toBeNull();
  });

  it("falls back to empty ward when metadata lacks it", () => {
    expect(ward(baseProperty({ metadata: {} as never }))).toBe("");
  });
});

describe("toDetail", () => {
  it("emits municipalValue as a 2dp decimal string and the rest from metadata", () => {
    const d = toDetail(baseProperty());
    expect(d.municipalValue).toBe("1850000.00");
    expect(d.extentSqm).toBe(495);
    expect(d.dataAsOf).toBe("2026-06-15T02:00:00.000Z");
  });

  it("coerces a numeric municipalValue to a 2dp string", () => {
    const d = toDetail(
      baseProperty({ metadata: { municipalValue: 1850000 } as never }),
    );
    expect(d.municipalValue).toBe("1850000.00");
  });
});
