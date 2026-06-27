import express, { type Express } from "express";
import multer from "multer";
import { fileTypeFromBuffer } from "file-type";
import { z } from "zod";
import {
  ApiError,
  asyncHandler,
  errorMiddleware,
  makeHealthHandler,
  notFoundMiddleware,
  ok,
  rateLimit,
} from "@easyrates/http";
import { prisma } from "@easyrates/db";
import {
  type AuthCoreRuntime,
  type AuthedRequest,
  parseOrValidationError,
  requireAuth,
} from "@easyrates/auth-core";
import {
  enqueueObjectionSubmit,
  pingQueue,
} from "@easyrates/queue";
import { putEvidence } from "./blob-store.js";
import {
  MAX_FILE_SIZE_BYTES,
  UPLOAD_CONFIG,
  decideDraftUpsert,
  toEvidenceResponse,
  toObjectionSummary,
  validateEvidenceFile,
  type ObjectionStatusResponse,
} from "./logic.js";

// ---- Validation (objection-service.md) -------------------------------------

const OBJECTION_CATEGORIES = [
  "WRONG_METER_READING",
  "INCORRECT_TARIFF",
  "PROPERTY_NOT_OCCUPIED",
  "DUPLICATE_OTHER",
] as const;

const OBJECTION_STATUSES = [
  "UNDER_REVIEW",
  "MORE_INFO_REQUESTED",
  "UPHELD",
  "REJECTED",
] as const;

const draftSchema = z.object({
  lineItemIds: z.array(z.string().min(1)).min(1, "At least one lineItemId is required."),
  category: z.enum(OBJECTION_CATEGORIES, {
    errorMap: () => ({ message: "Must be a valid ObjectionCategory." }),
  }),
  notes: z
    .string()
    .min(10, "Must be 10–2000 characters.")
    .max(2000, "Must be 10–2000 characters.")
    .optional(),
});

const listQuerySchema = z.object({
  page: z.coerce.number().int().min(1, "page must be ≥ 1.").default(1),
  pageSize: z.coerce
    .number()
    .int()
    .min(1, "pageSize must be ≥ 1.")
    .max(100, "pageSize must be ≤ 100.")
    .default(20),
  status: z.enum(OBJECTION_STATUSES).optional(),
});

/** The caller's municipality (single-tenant MVP) via their first active account. */
async function callerMunicipalityId(req: AuthedRequest): Promise<string> {
  const account = await prisma.account.findFirst({
    where: { userId: req.userId, deletedAt: null },
    select: { municipalityId: true },
  });
  if (!account) {
    throw ApiError.forbidden("No municipal account is linked to this user.");
  }
  return account.municipalityId;
}

/** Load an objection by id owned by the caller, or throw 404/403. */
async function ownedObjectionById(req: AuthedRequest, id: string) {
  const objection = await prisma.objection.findFirst({
    where: { id, deletedAt: null },
  });
  if (!objection) throw ApiError.notFound("Objection not found.");
  if (objection.userId !== req.userId) {
    throw ApiError.forbidden("Objection not owned by the caller.");
  }
  return objection;
}

export function createObjectionApp(rt: AuthCoreRuntime): Express {
  const app = express();
  app.use(express.json());

  const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: MAX_FILE_SIZE_BYTES },
  });

  app.get(
    "/health",
    makeHealthHandler({ serviceName: "objection-service", pingQueue }),
  );

  // ---- POST /objections/draft (UPSERT — one open draft per user) -----------
  // The durable Objection row is created here (born UNDER_REVIEW, refNumber/
  // submittedAt null = "not yet submitted") so evidence can FK to it; the
  // editable form state lives alongside in ObjectionDraft. Re-saving overwrites
  // both in place — 200, stable objectionId, no 409 for an existing draft.
  app.post(
    "/objections/draft",
    requireAuth(rt.tokens),
    rateLimit("WRITE"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const body = parseOrValidationError(draftSchema, req.body);
      const municipalityId = await callerMunicipalityId(req);

      // Single lineItem on the schema's Objection/ObjectionDraft — the dispute
      // anchor is the first disputed line item (schema/contract gap noted).
      const lineItemId = body.lineItemIds[0]!;
      const lineItem = await prisma.billLineItem.findUnique({
        where: { id: lineItemId },
        select: { id: true },
      });
      if (!lineItem) {
        throw ApiError.validation({ lineItemIds: "Unknown lineItemId." });
      }

      const [submitted, open] = await Promise.all([
        prisma.objection.findFirst({
          where: {
            userId: req.userId,
            lineItemId,
            deletedAt: null,
            refNumber: { not: null },
          },
          select: { id: true },
        }),
        prisma.objection.findFirst({
          where: {
            userId: req.userId,
            lineItemId,
            deletedAt: null,
            refNumber: null,
          },
          select: { id: true },
        }),
      ]);

      const decision = decideDraftUpsert({
        submittedObjectionExists: Boolean(submitted),
        openObjectionId: open?.id ?? null,
      });
      if (decision.action === "conflict") {
        throw ApiError.conflict(
          "A submitted objection already exists for one or more of these charges.",
        );
      }

      const objection =
        decision.action === "overwrite"
          ? await prisma.objection.update({
              where: { id: decision.objectionId },
              data: { category: body.category, notes: body.notes ?? null },
            })
          : await prisma.objection.create({
              data: {
                userId: req.userId!,
                municipalityId,
                lineItemId,
                category: body.category,
                status: "UNDER_REVIEW",
                notes: body.notes ?? null,
              },
            });

      // UPSERT the editable draft form state (one per user+lineItem).
      const draft = await prisma.objectionDraft.findFirst({
        where: { userId: req.userId, lineItemId },
      });
      if (draft) {
        await prisma.objectionDraft.update({
          where: { id: draft.id },
          data: { category: body.category, notes: body.notes ?? null },
        });
      } else {
        await prisma.objectionDraft.create({
          data: {
            userId: req.userId!,
            lineItemId,
            category: body.category,
            notes: body.notes ?? null,
          },
        });
      }

      res.status(200).json(
        ok({
          objectionId: objection.id,
          status: "DRAFT" as const,
          uploadConfig: UPLOAD_CONFIG,
        }),
      );
    }),
  );

  // ---- POST /objections/:id/evidence (multipart) ---------------------------
  app.post(
    "/objections/:id/evidence",
    requireAuth(rt.tokens),
    rateLimit("WRITE"),
    upload.single("file"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const objection = await ownedObjectionById(req, req.params.id!);

      const file = req.file;
      const existingCount = await prisma.evidenceFile.count({
        where: { objectionId: objection.id, deletedAt: null },
      });

      // Magic-byte detection — the declared Content-Type is NOT trusted (Rule C).
      const detected = file
        ? (await fileTypeFromBuffer(file.buffer))?.mime
        : undefined;

      const verdict = validateEvidenceFile({
        hasFile: Boolean(file),
        sizeBytes: file?.size ?? 0,
        detectedType: detected,
        existingCount,
      });

      if (!verdict.ok) {
        switch (verdict.reason) {
          case "missing":
            throw new ApiError("file_missing", 400, "No file part in the request.");
          case "too_large":
            // multer's limit usually fires first (413 below); belt-and-braces.
            throw new ApiError(
              "rate_limit_exceeded",
              413,
              "File exceeds the 10 MB limit.",
              { maxFileSizeBytes: MAX_FILE_SIZE_BYTES },
            );
          case "too_many":
            throw ApiError.unprocessable(
              "Maximum number of evidence files reached.",
              { maxFilesPerObjection: UPLOAD_CONFIG.maxFilesPerObjection },
            );
          case "invalid_type":
            throw new ApiError(
              "invalid_file_type",
              422,
              "File type not supported. Upload PDF, JPG, or PNG only.",
              {
                detectedType: verdict.detectedType,
                allowedTypes: UPLOAD_CONFIG.acceptedMimeTypes,
              },
            );
        }
      }

      const detectedType = detected!;
      const storageKey = await putEvidence({
        objectionId: objection.id,
        detectedType,
        bytes: file!.buffer,
      });

      const saved = await prisma.evidenceFile.create({
        data: {
          objectionId: objection.id,
          storageKey,
          filename: file!.originalname,
          mimeType: detectedType, // the DETECTED type, not the declared header
        },
      });

      // MORE_INFO_REQUESTED → an upload auto-transitions back to UNDER_REVIEW.
      if (objection.status === "MORE_INFO_REQUESTED") {
        await prisma.objection.update({
          where: { id: objection.id },
          data: { status: "UNDER_REVIEW" },
        });
      }

      res.status(201).json(ok(toEvidenceResponse(saved, file!.size)));
    }),
  );

  // ---- POST /objections/:id/submit (async 202) -----------------------------
  app.post(
    "/objections/:id/submit",
    requireAuth(rt.tokens),
    rateLimit("SUBMIT"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const objection = await ownedObjectionById(req, req.params.id!);

      // Already submitted → 409 conflict.
      if (objection.refNumber) {
        throw ApiError.conflict("This objection has already been submitted.");
      }

      // Semantically require at least one evidence file (422 if incomplete).
      const evidenceCount = await prisma.evidenceFile.count({
        where: { objectionId: objection.id, deletedAt: null },
      });
      if (evidenceCount === 0) {
        throw ApiError.unprocessable(
          "Attach at least one evidence document before submitting.",
        );
      }

      const jobId = await enqueueObjectionSubmit({
        objectionId: objection.id,
        userId: req.userId!,
      });
      if (!jobId) {
        throw new ApiError(
          "internal_server_error",
          503,
          "Submission queue is temporarily unavailable. Please try again.",
        );
      }

      res.status(202).json(
        ok({
          jobId,
          statusUrl: `/api/v1/objections/${jobId}/status`,
        }),
      );
    }),
  );

  // ---- GET /objections (paginated, optional status filter) -----------------
  app.get(
    "/objections",
    requireAuth(rt.tokens),
    rateLimit("READ"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const { page, pageSize, status } = parseOrValidationError(
        listQuerySchema,
        req.query,
      );

      // Only SUBMITTED objections (those with a refNumber) appear in Tracking.
      const where = {
        userId: req.userId,
        deletedAt: null,
        refNumber: { not: null },
        ...(status ? { status } : {}),
      };

      const [total, rows] = await Promise.all([
        prisma.objection.count({ where }),
        prisma.objection.findMany({
          where,
          orderBy: { createdAt: "desc" },
          skip: (page - 1) * pageSize,
          take: pageSize,
          include: {
            lineItem: {
              select: {
                description: true,
                bill: { select: { accountNumber: true } },
              },
            },
          },
        }),
      ]);

      // Resolve property labels per accountNumber (one query).
      const accountNumbers = [
        ...new Set(rows.map((r) => r.lineItem.bill.accountNumber)),
      ];
      const properties = await prisma.property.findMany({
        where: { accountNumber: { in: accountNumbers } },
        select: { accountNumber: true, address: true },
      });
      const addressByAccount = new Map(
        properties.map((p) => [p.accountNumber, p.address]),
      );

      const items = rows.map((r) =>
        toObjectionSummary({
          objection: r,
          lineItemDescription: r.lineItem.description,
          propertyLabel:
            addressByAccount.get(r.lineItem.bill.accountNumber) ?? "",
        }),
      );

      res.status(200).json(
        ok({
          items,
          page,
          pageSize,
          total,
          totalPages: Math.ceil(total / pageSize),
        }),
      );
    }),
  );

  // ---- GET /objections/:ref/status -----------------------------------------
  app.get(
    "/objections/:ref/status",
    requireAuth(rt.tokens),
    rateLimit("READ"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const objection = await prisma.objection.findFirst({
        where: { refNumber: req.params.ref, deletedAt: null },
        include: {
          lineItem: {
            select: {
              id: true,
              description: true,
              amount: true,
              bill: { select: { aiCalculation: { select: { estimatedAmount: true, confidence: true } } } },
            },
          },
          municipalityResponses: { orderBy: { respondedAt: "asc" } },
        },
      });
      if (!objection) throw ApiError.notFound("No objection with that refNumber.");
      if (objection.userId !== req.userId) {
        throw ApiError.forbidden("Objection not owned by the caller.");
      }

      // Timeline: submission + each municipality response, in order.
      const timeline: ObjectionStatusResponse["statusTimeline"] = [];
      if (objection.submittedAt) {
        timeline.push({
          status: "UNDER_REVIEW",
          at: objection.submittedAt.toISOString(),
          note: "Submitted.",
        });
      }
      for (const r of objection.municipalityResponses) {
        timeline.push({
          status: r.status,
          at: r.respondedAt.toISOString(),
          note: r.note ?? "",
        });
      }

      const latest =
        objection.municipalityResponses[
          objection.municipalityResponses.length - 1
        ] ?? null;

      const aiCalc = objection.lineItem.bill.aiCalculation;
      const expectedAmount =
        aiCalc && aiCalc.confidence >= 0.85
          ? aiCalc.estimatedAmount.toFixed(2)
          : null;

      const payload: ObjectionStatusResponse = {
        refNumber: objection.refNumber!,
        status: objection.status,
        submittedAt: (objection.submittedAt ?? objection.createdAt).toISOString(),
        lastUpdatedAt: objection.updatedAt.toISOString(),
        statusTimeline: timeline,
        disputedItems: [
          {
            lineItemId: objection.lineItem.id,
            label: objection.lineItem.description,
            chargedAmount: objection.lineItem.amount.toFixed(2),
            expectedAmount,
            category: objection.category,
          },
        ],
        municipalityResponse: latest
          ? {
              note: latest.note ?? "",
              adjustedAmount:
                latest.adjustedAmount == null
                  ? null
                  : latest.adjustedAmount.toFixed(2),
            }
          : null,
      };

      res.status(200).json(ok(payload));
    }),
  );

  // multer LIMIT_FILE_SIZE → 413 (conventions: payload too large).
  app.use(
    (
      err: unknown,
      _req: express.Request,
      res: express.Response,
      next: express.NextFunction,
    ) => {
      if (err instanceof multer.MulterError && err.code === "LIMIT_FILE_SIZE") {
        res.status(413).json({
          data: null,
          error: {
            code: "rate_limit_exceeded",
            message: "File exceeds the 10 MB limit.",
            details: { maxFileSizeBytes: MAX_FILE_SIZE_BYTES },
          },
        });
        return;
      }
      next(err);
    },
  );

  app.use(notFoundMiddleware);
  app.use(errorMiddleware);
  return app;
}
