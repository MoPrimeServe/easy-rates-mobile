import { Prisma } from "@easyrates/db";
import type {
  EvidenceFile,
  Objection,
  ObjectionCategory,
  ObjectionStatus,
} from "@easyrates/db";

/**
 * objection-service business logic — pure, side-effect-free helpers shared by
 * the route handlers and unit tests (matches the bill/account `logic.ts`
 * pattern). HTTP/DB live in app.ts; the decisions worth testing live here.
 */

// ---- Upload config (docs/security/upload-validation.md, mirrored in the contract) ----
export const MAX_FILE_SIZE_BYTES = 10485760; // 10 MiB
export const ACCEPTED_MIME_TYPES = [
  "application/pdf",
  "image/jpeg",
  "image/png",
] as const;
export const MAX_FILES_PER_OBJECTION = 5;

export interface UploadConfig {
  maxFileSizeBytes: number;
  acceptedMimeTypes: string[];
  maxFilesPerObjection: number;
}

export const UPLOAD_CONFIG: UploadConfig = {
  maxFileSizeBytes: MAX_FILE_SIZE_BYTES,
  acceptedMimeTypes: [...ACCEPTED_MIME_TYPES],
  maxFilesPerObjection: MAX_FILES_PER_OBJECTION,
};

// ---- Response shapes (objection-service.md TypeScript interfaces) ----
export interface ObjectionDraftResponse {
  objectionId: string;
  status: "DRAFT";
  uploadConfig: UploadConfig;
}

export interface EvidenceUploadResponse {
  evidenceId: string;
  filename: string;
  mimeType: string;
  sizeBytes: number;
  uploadedAt: string;
}

export interface ObjectionSummary {
  refNumber: string;
  category: ObjectionCategory;
  status: ObjectionStatus;
  title: string;
  propertyLabel: string;
  createdAt: string;
}

export interface MunicipalityResponseView {
  note: string;
  adjustedAmount: string | null;
}

export interface StatusTimelineEntry {
  status: ObjectionStatus;
  at: string;
  note: string;
}

export interface DisputedItem {
  lineItemId: string;
  label: string;
  chargedAmount: string;
  expectedAmount: string | null;
  category: ObjectionCategory;
}

export interface ObjectionStatusResponse {
  refNumber: string;
  status: ObjectionStatus;
  submittedAt: string;
  lastUpdatedAt: string;
  statusTimeline: StatusTimelineEntry[];
  disputedItems: DisputedItem[];
  municipalityResponse: MunicipalityResponseView | null;
}

// ---- File validation -------------------------------------------------------

export type FileValidation =
  | { ok: true }
  | { ok: false; reason: "missing" }
  | { ok: false; reason: "too_large" }
  | { ok: false; reason: "invalid_type"; detectedType: string }
  | { ok: false; reason: "too_many" };

/**
 * Validate an evidence file against the upload config. `detectedType` is the
 * magic-byte-sniffed MIME (NOT the client header — Rule C). `existingCount` is
 * how many non-deleted evidence files the objection already has.
 *
 * Returns a discriminated result the route maps onto the contract's status
 * codes: missing → 400 file_missing, too_large → 413, invalid_type → 422
 * invalid_file_type, too_many → 422.
 */
export function validateEvidenceFile(args: {
  hasFile: boolean;
  sizeBytes: number;
  detectedType: string | undefined;
  existingCount: number;
}): FileValidation {
  if (!args.hasFile) return { ok: false, reason: "missing" };
  if (args.existingCount >= MAX_FILES_PER_OBJECTION) {
    return { ok: false, reason: "too_many" };
  }
  if (args.sizeBytes > MAX_FILE_SIZE_BYTES) {
    return { ok: false, reason: "too_large" };
  }
  const detected = args.detectedType ?? "unknown";
  if (!ACCEPTED_MIME_TYPES.includes(detected as (typeof ACCEPTED_MIME_TYPES)[number])) {
    return { ok: false, reason: "invalid_type", detectedType: detected };
  }
  return { ok: true };
}

// ---- Draft upsert decision -------------------------------------------------

export type DraftUpsertDecision =
  | { action: "conflict" } // a submitted objection already covers the charge
  | { action: "overwrite"; objectionId: string } // an open draft exists → overwrite in place
  | { action: "create" }; // no open draft → create

/**
 * Decide what `POST /objections/draft` should do, given what already exists for
 * this user+lineItem. Pure so the UPSERT contract ("one open draft; create or
 * overwrite; 200 either way; 409 only for a *submitted* objection") is testable
 * without a DB.
 *
 *  - A SUBMITTED objection (refNumber assigned) covering the charge → conflict (409).
 *  - An OPEN pre-submission Objection (refNumber null) → overwrite it (200, stable id).
 *  - Nothing → create (200).
 */
export function decideDraftUpsert(args: {
  submittedObjectionExists: boolean;
  openObjectionId: string | null;
}): DraftUpsertDecision {
  if (args.submittedObjectionExists) return { action: "conflict" };
  if (args.openObjectionId) {
    return { action: "overwrite", objectionId: args.openObjectionId };
  }
  return { action: "create" };
}

// ---- Mappers ---------------------------------------------------------------

function money(d: Prisma.Decimal | number | string): string {
  return new Prisma.Decimal(d).toFixed(2);
}

/** Short server-composed list label for the Tracking row. */
export function objectionTitle(
  lineItemDescription: string | null,
  propertyLabel: string,
): string {
  const desc = lineItemDescription?.trim() || "Objection";
  const shortAddress = propertyLabel.split(",")[0]?.trim() ?? propertyLabel;
  return `${desc} — ${shortAddress}`;
}

export function toObjectionSummary(args: {
  objection: Pick<
    Objection,
    "refNumber" | "category" | "status" | "createdAt"
  >;
  lineItemDescription: string | null;
  propertyLabel: string;
}): ObjectionSummary {
  return {
    refNumber: args.objection.refNumber ?? "",
    category: args.objection.category,
    status: args.objection.status,
    title: objectionTitle(args.lineItemDescription, args.propertyLabel),
    propertyLabel: args.propertyLabel,
    createdAt: args.objection.createdAt.toISOString(),
  };
}

export function toEvidenceResponse(
  file: Pick<
    EvidenceFile,
    "id" | "filename" | "mimeType" | "uploadedAt"
  >,
  sizeBytes: number,
): EvidenceUploadResponse {
  return {
    evidenceId: file.id,
    filename: file.filename,
    mimeType: file.mimeType,
    sizeBytes,
    uploadedAt: file.uploadedAt.toISOString(),
  };
}

export { money };
