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

// ---- Sufficiency (GET /objections/:id/sufficiency) -------------------------

export interface SufficiencyMissingEntry {
  category: ObjectionCategory;
  requiredDocTypes: string[];
}

export interface ObjectionSufficiencyResponse {
  objectionId: string;
  sufficient: boolean;
  missing: SufficiencyMissingEntry[];
}

/**
 * Rule-based evidence requirements per dispute category (MVP — AI content
 * verification is post-MVP, per the contract). Each category lists the doc
 * types the user is expected to attach; `minDocs` is the minimum file count
 * that satisfies the rule for the MVP.
 */
export const SUFFICIENCY_RULES: Record<
  ObjectionCategory,
  { requiredDocTypes: string[]; minDocs: number }
> = {
  WRONG_METER_READING: {
    requiredDocTypes: ["meter_photo", "previous_reading"],
    minDocs: 1,
  },
  INCORRECT_TARIFF: { requiredDocTypes: ["tariff_proof"], minDocs: 1 },
  PROPERTY_NOT_OCCUPIED: {
    requiredDocTypes: ["vacancy_proof"],
    minDocs: 1,
  },
  DUPLICATE_OTHER: { requiredDocTypes: ["supporting_document"], minDocs: 1 },
};

/**
 * Decide whether the attached evidence is sufficient for the category. Pure so
 * the rule is testable without a DB. `sufficient = true` → `missing` is empty;
 * `false` → `missing` carries the one entry for this objection's category.
 */
export function evaluateSufficiency(args: {
  objectionId: string;
  category: ObjectionCategory;
  evidenceCount: number;
}): ObjectionSufficiencyResponse {
  const rule = SUFFICIENCY_RULES[args.category];
  const sufficient = args.evidenceCount >= rule.minDocs;
  return {
    objectionId: args.objectionId,
    sufficient,
    missing: sufficient
      ? []
      : [{ category: args.category, requiredDocTypes: rule.requiredDocTypes }],
  };
}

// ---- Summary (GET /objections/:id/summary) ---------------------------------

export interface SummaryDocument {
  evidenceId: string;
  filename: string;
  mimeType: string;
}

export interface ObjectionSummaryResponse {
  objectionId: string;
  property: { accountNumber: string; address: string };
  billingPeriod: string;
  disputedItems: DisputedItem[];
  documents: SummaryDocument[];
  totalDisputedAmount: string;
}

/** Confidence floor at/above which the AI estimate is surfaced as expectedAmount. */
export const EXPECTED_AMOUNT_CONFIDENCE_FLOOR = 0.85;

/**
 * Resolve the AI-estimated `expectedAmount` for a disputed line item: the
 * estimate is surfaced (as a 2dp decimal string) only when the AI calculation
 * exists AND clears the confidence floor; otherwise it is null. Pure/testable.
 */
export function expectedAmountFromAi(
  ai: { estimatedAmount: Prisma.Decimal | number | string; confidence: number } | null,
): string | null {
  if (!ai || ai.confidence < EXPECTED_AMOUNT_CONFIDENCE_FLOOR) return null;
  return money(ai.estimatedAmount);
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
