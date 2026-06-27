import { describe, it, expect, afterAll } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { decideBlobDriver, LocalBlobStore } from "./blob-store.js";

describe("decideBlobDriver (env-driven selection)", () => {
  it("auto + connection string present → azure", () => {
    expect(decideBlobDriver("auto", true)).toBe("azure");
  });
  it("auto + no connection string → local (default-safe)", () => {
    expect(decideBlobDriver("auto", false)).toBe("local");
  });
  it("azure forces azure even without a string (will error later, by design)", () => {
    expect(decideBlobDriver("azure", false)).toBe("azure");
  });
  it("local forces local even when a string is present", () => {
    expect(decideBlobDriver("local", true)).toBe("local");
  });
});

describe("LocalBlobStore round-trip", () => {
  const created: string[] = [];

  afterAll(async () => {
    for (const dir of created) await rm(dir, { recursive: true, force: true });
  });

  it("put → get returns identical bytes; delete removes it; key shape is portable", async () => {
    const dir = await mkdtemp(join(tmpdir(), "evidence-"));
    created.push(dir);
    const prevCwd = process.cwd();
    process.chdir(dir); // LocalBlobStore resolves BLOB_DIR relative to cwd
    try {
      const store = new LocalBlobStore();
      const bytes = Buffer.from("%PDF-1.4 test evidence");
      const key = await store.put({
        objectionId: "obj123",
        detectedType: "application/pdf",
        bytes,
      });
      // objections/<objectionId>/<uuid>.pdf — the Azure-portable shape
      expect(key).toMatch(/^objections\/obj123\/[0-9a-f-]+\.pdf$/);

      const got = await store.get(key);
      expect(got.equals(bytes)).toBe(true);

      await store.delete(key);
      await expect(store.get(key)).rejects.toBeTruthy();
      // delete is idempotent — second delete does not throw
      await expect(store.delete(key)).resolves.toBeUndefined();
    } finally {
      process.chdir(prevCwd);
    }
  });
});
