import { mkdir, writeFile } from "node:fs/promises";
import { resolve, join } from "node:path";
import { randomUUID } from "node:crypto";
import { env } from "@easyrates/config";

/**
 * Local blob-storage STUB for objection evidence.
 *
 * Azure Blob Storage is the production target (see EvidenceFile.storageKey, the
 * data model, and the Azure note in CLAUDE.md). For local dev we persist the
 * bytes under BLOB_DIR and record the relative storageKey on EvidenceFile — the
 * same key shape a real container would use, so swapping in an Azure adapter is
 * a one-file change here.
 */

const EXT_BY_MIME: Record<string, string> = {
  "application/pdf": "pdf",
  "image/jpeg": "jpg",
  "image/png": "png",
};

function blobRoot(): string {
  return resolve(process.cwd(), env.BLOB_DIR);
}

/**
 * Store the evidence bytes and return the storage key. Key shape:
 * `objections/<objectionId>/<uuid>.<ext>` — stable, collision-free, and
 * directly portable to an Azure container path.
 */
export async function putEvidence(args: {
  objectionId: string;
  detectedType: string;
  bytes: Buffer;
}): Promise<string> {
  const ext = EXT_BY_MIME[args.detectedType] ?? "bin";
  const key = `objections/${args.objectionId}/${randomUUID()}.${ext}`;
  const fullPath = join(blobRoot(), key);
  await mkdir(join(blobRoot(), "objections", args.objectionId), {
    recursive: true,
  });
  await writeFile(fullPath, args.bytes);
  return key;
}
