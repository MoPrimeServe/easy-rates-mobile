import { mkdir, writeFile, readFile, unlink } from "node:fs/promises";
import { resolve, join, dirname } from "node:path";
import { randomUUID } from "node:crypto";
import {
  BlobServiceClient,
  type ContainerClient,
} from "@azure/storage-blob";
import { env } from "@easyrates/config";

/**
 * Objection-evidence blob storage behind one interface.
 *
 *  - AzureBlobStore — production target. `BlobServiceClient.fromConnectionString`
 *    against the `evidence` container (auto-created if absent). Selected when a
 *    connection string is present (BLOB_DRIVER=auto|azure).
 *  - LocalBlobStore — filesystem stub under BLOB_DIR (gitignored). The dev
 *    fallback when no Azure connection string is set (BLOB_DRIVER=auto|local).
 *
 * Both use the SAME storageKey shape — `objections/<objectionId>/<uuid>.<ext>` —
 * so EvidenceFile.storageKey is portable across backends.
 */

export interface EvidenceStore {
  /** Store bytes; returns the storageKey recorded on EvidenceFile. */
  put(args: {
    objectionId: string;
    detectedType: string;
    bytes: Buffer;
  }): Promise<string>;
  /** Read bytes back by storageKey. */
  get(storageKey: string): Promise<Buffer>;
  /** Delete the object by storageKey (idempotent). */
  delete(storageKey: string): Promise<void>;
}

const EXT_BY_MIME: Record<string, string> = {
  "application/pdf": "pdf",
  "image/jpeg": "jpg",
  "image/png": "png",
};

/** `objections/<objectionId>/<uuid>.<ext>` — stable, collision-free key. */
function buildKey(objectionId: string, detectedType: string): string {
  const ext = EXT_BY_MIME[detectedType] ?? "bin";
  return `objections/${objectionId}/${randomUUID()}.${ext}`;
}

// ---- Local filesystem stub --------------------------------------------------

export class LocalBlobStore implements EvidenceStore {
  private root(): string {
    return resolve(process.cwd(), env.BLOB_DIR);
  }

  async put(args: {
    objectionId: string;
    detectedType: string;
    bytes: Buffer;
  }): Promise<string> {
    const key = buildKey(args.objectionId, args.detectedType);
    const fullPath = join(this.root(), key);
    await mkdir(dirname(fullPath), { recursive: true });
    await writeFile(fullPath, args.bytes);
    return key;
  }

  async get(storageKey: string): Promise<Buffer> {
    return readFile(join(this.root(), storageKey));
  }

  async delete(storageKey: string): Promise<void> {
    await unlink(join(this.root(), storageKey)).catch(() => undefined);
  }
}

// ---- Azure Blob Storage -----------------------------------------------------

export class AzureBlobStore implements EvidenceStore {
  private readonly container: ContainerClient;
  private ensured = false;

  constructor(connectionString: string, containerName: string) {
    const service = BlobServiceClient.fromConnectionString(connectionString);
    this.container = service.getContainerClient(containerName);
  }

  /** Lazily create the container (private) once per process. */
  private async ensureContainer(): Promise<void> {
    if (this.ensured) return;
    await this.container.createIfNotExists();
    this.ensured = true;
  }

  async put(args: {
    objectionId: string;
    detectedType: string;
    bytes: Buffer;
  }): Promise<string> {
    await this.ensureContainer();
    const key = buildKey(args.objectionId, args.detectedType);
    const block = this.container.getBlockBlobClient(key);
    await block.uploadData(args.bytes, {
      blobHTTPHeaders: { blobContentType: args.detectedType },
    });
    return key;
  }

  async get(storageKey: string): Promise<Buffer> {
    await this.ensureContainer();
    const block = this.container.getBlockBlobClient(storageKey);
    return block.downloadToBuffer();
  }

  async delete(storageKey: string): Promise<void> {
    await this.ensureContainer();
    const block = this.container.getBlockBlobClient(storageKey);
    await block.deleteIfExists();
  }
}

// ---- Selection (env-driven, default-safe) -----------------------------------

let singleton: EvidenceStore | null = null;

/**
 * Pure backend-selection decision: azure when forced, or when "auto" and a
 * connection string is present; otherwise local. Exported for unit testing.
 */
export function decideBlobDriver(
  driver: "auto" | "azure" | "local",
  hasConnectionString: boolean,
): "azure" | "local" {
  if (driver === "azure") return "azure";
  if (driver === "local") return "local";
  return hasConnectionString ? "azure" : "local";
}

/** Resolve which backend to use: azure when a connection string is present and
 * BLOB_DRIVER allows it, else the local stub. */
export function selectEvidenceStore(): EvidenceStore {
  if (singleton) return singleton;
  const hasAzure = Boolean(env.AZURE_STORAGE_CONNECTION_STRING);
  const useAzure =
    decideBlobDriver(env.BLOB_DRIVER, hasAzure) === "azure";

  if (useAzure) {
    if (!env.AZURE_STORAGE_CONNECTION_STRING) {
      throw new Error(
        "[blob-store] BLOB_DRIVER=azure but AZURE_STORAGE_CONNECTION_STRING is unset.",
      );
    }
    singleton = new AzureBlobStore(
      env.AZURE_STORAGE_CONNECTION_STRING,
      env.AZURE_BLOB_CONTAINER,
    );
    console.log(
      `[blob-store] evidence backend: Azure Blob (container=${env.AZURE_BLOB_CONTAINER}).`,
    );
  } else {
    singleton = new LocalBlobStore();
    console.log(`[blob-store] evidence backend: local stub (dir=${env.BLOB_DIR}).`);
  }
  return singleton;
}

/** Backwards-compatible helper used by the route handler (selects + puts). */
export async function putEvidence(args: {
  objectionId: string;
  detectedType: string;
  bytes: Buffer;
}): Promise<string> {
  return selectEvidenceStore().put(args);
}
