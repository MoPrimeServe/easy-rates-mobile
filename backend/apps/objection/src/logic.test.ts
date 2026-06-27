import { describe, expect, it } from "vitest";
import {
  MAX_FILE_SIZE_BYTES,
  UPLOAD_CONFIG,
  decideDraftUpsert,
  evaluateSufficiency,
  expectedAmountFromAi,
  objectionTitle,
  validateEvidenceFile,
} from "./logic.js";

describe("decideDraftUpsert — UPSERT contract (200 either way; 409 only for submitted)", () => {
  it("creates when no open draft and no submitted objection exist", () => {
    expect(
      decideDraftUpsert({ submittedObjectionExists: false, openObjectionId: null }),
    ).toEqual({ action: "create" });
  });

  it("overwrites the existing open draft in place (stable id, no 409)", () => {
    expect(
      decideDraftUpsert({ submittedObjectionExists: false, openObjectionId: "obj_1" }),
    ).toEqual({ action: "overwrite", objectionId: "obj_1" });
  });

  it("conflicts (409) only when a submitted objection already covers the charge", () => {
    expect(
      decideDraftUpsert({ submittedObjectionExists: true, openObjectionId: null }),
    ).toEqual({ action: "conflict" });
  });

  it("submitted conflict wins even if an open draft also exists", () => {
    expect(
      decideDraftUpsert({ submittedObjectionExists: true, openObjectionId: "obj_1" }),
    ).toEqual({ action: "conflict" });
  });
});

describe("validateEvidenceFile — size / MIME / count", () => {
  const base = {
    hasFile: true,
    sizeBytes: 1024,
    detectedType: "application/pdf",
    existingCount: 0,
  };

  it("accepts a valid PDF under the limit and within the count", () => {
    expect(validateEvidenceFile(base)).toEqual({ ok: true });
  });

  it("accepts JPEG and PNG", () => {
    expect(validateEvidenceFile({ ...base, detectedType: "image/jpeg" }).ok).toBe(true);
    expect(validateEvidenceFile({ ...base, detectedType: "image/png" }).ok).toBe(true);
  });

  it("rejects a missing file with reason=missing", () => {
    expect(validateEvidenceFile({ ...base, hasFile: false })).toEqual({
      ok: false,
      reason: "missing",
    });
  });

  it("rejects an oversized file with reason=too_large", () => {
    expect(
      validateEvidenceFile({ ...base, sizeBytes: MAX_FILE_SIZE_BYTES + 1 }),
    ).toEqual({ ok: false, reason: "too_large" });
  });

  it("rejects a disallowed MIME with detectedType echoed", () => {
    expect(
      validateEvidenceFile({ ...base, detectedType: "application/zip" }),
    ).toEqual({ ok: false, reason: "invalid_type", detectedType: "application/zip" });
  });

  it("treats an unrecognised (undefined) magic-byte type as invalid → 'unknown'", () => {
    expect(
      validateEvidenceFile({ ...base, detectedType: undefined }),
    ).toEqual({ ok: false, reason: "invalid_type", detectedType: "unknown" });
  });

  it("rejects once the per-objection file count is reached", () => {
    expect(
      validateEvidenceFile({
        ...base,
        existingCount: UPLOAD_CONFIG.maxFilesPerObjection,
      }),
    ).toEqual({ ok: false, reason: "too_many" });
  });

  it("count check precedes size/type checks (full objection short-circuits)", () => {
    expect(
      validateEvidenceFile({
        ...base,
        existingCount: 5,
        sizeBytes: MAX_FILE_SIZE_BYTES + 1,
        detectedType: "application/zip",
      }),
    ).toEqual({ ok: false, reason: "too_many" });
  });
});

describe("upload config mirrors the contract", () => {
  it("matches maxFileSizeBytes / mimeTypes / maxFiles exactly", () => {
    expect(UPLOAD_CONFIG).toEqual({
      maxFileSizeBytes: 10485760,
      acceptedMimeTypes: ["application/pdf", "image/jpeg", "image/png"],
      maxFilesPerObjection: 5,
    });
  });
});

describe("objectionTitle", () => {
  it("composes '<line desc> — <street>' from the address head", () => {
    expect(
      objectionTitle("Water consumption", "12 Vaal Street, Vanderbijlpark"),
    ).toBe("Water consumption — 12 Vaal Street");
  });
  it("falls back to 'Objection' when the line description is empty", () => {
    expect(objectionTitle(null, "12 Vaal Street, Vanderbijlpark")).toBe(
      "Objection — 12 Vaal Street",
    );
  });
});

describe("evaluateSufficiency — rule-based MVP", () => {
  it("is sufficient when evidence meets the category minimum (empty missing)", () => {
    const r = evaluateSufficiency({
      objectionId: "obj_1",
      category: "WRONG_METER_READING",
      evidenceCount: 1,
    });
    expect(r).toEqual({ objectionId: "obj_1", sufficient: true, missing: [] });
  });

  it("is insufficient with no evidence, surfacing the category's required doc types", () => {
    const r = evaluateSufficiency({
      objectionId: "obj_1",
      category: "WRONG_METER_READING",
      evidenceCount: 0,
    });
    expect(r.sufficient).toBe(false);
    expect(r.missing).toEqual([
      {
        category: "WRONG_METER_READING",
        requiredDocTypes: ["meter_photo", "previous_reading"],
      },
    ]);
  });

  it("covers every ObjectionCategory in the rules table", () => {
    for (const category of [
      "WRONG_METER_READING",
      "INCORRECT_TARIFF",
      "PROPERTY_NOT_OCCUPIED",
      "DUPLICATE_OTHER",
    ] as const) {
      const r = evaluateSufficiency({ objectionId: "o", category, evidenceCount: 0 });
      expect(r.sufficient).toBe(false);
      expect(r.missing[0]!.requiredDocTypes.length).toBeGreaterThan(0);
    }
  });
});

describe("expectedAmountFromAi — confidence floor 0.85", () => {
  it("surfaces the estimate as a 2dp string at/above the floor", () => {
    expect(expectedAmountFromAi({ estimatedAmount: "620", confidence: 0.85 })).toBe(
      "620.00",
    );
    expect(expectedAmountFromAi({ estimatedAmount: 620.5, confidence: 0.99 })).toBe(
      "620.50",
    );
  });
  it("returns null below the floor or when no estimate exists", () => {
    expect(expectedAmountFromAi({ estimatedAmount: "620", confidence: 0.5 })).toBeNull();
    expect(expectedAmountFromAi(null)).toBeNull();
  });
});
