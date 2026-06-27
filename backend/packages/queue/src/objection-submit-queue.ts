import { Queue, Worker, type ConnectionOptions, type Job } from "bullmq";
import { prisma } from "@easyrates/db";
import { writeAudit } from "@easyrates/http";
import { getMunicipalitySubmissionAdapter } from "@easyrates/adapters";
import { getQueueConnection } from "./connection.js";
import { enqueueNotification } from "./notification-queue.js";

/**
 * objection-submit queue — the async submission path. `POST /objections/:id/submit`
 * returns 202 immediately and enqueues here; the worker finalises the
 * submission: it assigns a refNumber (ELM-2026-NNNNNN), stamps `submittedAt`,
 * consumes the editable ObjectionDraft, and enqueues an OBJECTION_RECEIVED
 * notification.
 *
 * Schema/contract reconciliation (noted in the plan): EvidenceFile carries a
 * NON-NULL FK to Objection, so evidence cannot attach to a bare ObjectionDraft.
 * The objection-service therefore creates the durable Objection row at
 * draft-upsert time (born UNDER_REVIEW, but with refNumber = null and
 * submittedAt = null — those two nulls are the "not yet submitted" marker) and
 * co-stores the editable form state in ObjectionDraft. This worker turns that
 * pre-submission Objection into a submitted one. `:id` in the routes is the
 * Objection.id (returned to the client as `objectionId`).
 *
 * Idempotency: the job id is the objection id, so resubmitting does not create a
 * second in-flight job, and an objection that already has a refNumber is a no-op.
 */
export const OBJECTION_SUBMIT_QUEUE_NAME = "objection-submit";

export interface ObjectionSubmitJobData {
  /** Objection.id being submitted. Also used as the BullMQ job id. */
  objectionId: string;
  /** Authenticated user id (owner). */
  userId: string;
}

let objectionSubmitQueueSingleton: Queue<ObjectionSubmitJobData> | null = null;

export function getObjectionSubmitQueue(): Queue<ObjectionSubmitJobData> | null {
  const connection = getQueueConnection();
  if (!connection) return null;
  if (objectionSubmitQueueSingleton) return objectionSubmitQueueSingleton;
  objectionSubmitQueueSingleton = new Queue(OBJECTION_SUBMIT_QUEUE_NAME, {
    connection: connection as unknown as ConnectionOptions,
  }) as Queue<ObjectionSubmitJobData>;
  return objectionSubmitQueueSingleton;
}

/**
 * Enqueue an objection submission. Returns the BullMQ job id (== objectionId) on
 * success, or null when Redis is unavailable (the route then surfaces the queue
 * as down rather than minting a fake handle).
 */
export async function enqueueObjectionSubmit(
  data: ObjectionSubmitJobData,
): Promise<string | null> {
  const queue = getObjectionSubmitQueue();
  if (!queue) {
    console.warn(
      "[queue:objection-submit] Redis unavailable — cannot enqueue submit for objection:",
      data.objectionId,
    );
    return null;
  }
  const job = await queue.add("submit", data, {
    jobId: data.objectionId, // idempotency: one in-flight job per objection
    removeOnComplete: 1000,
    removeOnFail: 5000,
    attempts: 3,
    backoff: { type: "exponential", delay: 2000 },
  });
  return job.id ?? data.objectionId;
}

/**
 * Finalise an objection submission. Exported so the worker and unit tests share
 * one path. Idempotent: an objection that already has a refNumber (already
 * submitted) is returned unchanged.
 */
export async function processObjectionSubmitJob(
  data: ObjectionSubmitJobData,
): Promise<{ objectionId: string; refNumber: string } | null> {
  const objection = await prisma.objection.findUnique({
    where: { id: data.objectionId },
  });
  if (!objection) {
    console.warn(
      "[queue:objection-submit] objection not found:",
      data.objectionId,
    );
    return null;
  }
  // Already submitted → idempotent no-op.
  if (objection.refNumber) {
    return { objectionId: objection.id, refNumber: objection.refNumber };
  }

  // Submit through the MunicipalitySubmissionAdapter (default stub mints the ELM
  // ref locally; a real CRM impl swaps in here without touching this worker).
  const { refNumber } = await getMunicipalitySubmissionAdapter().submit({
    objectionId: objection.id,
    userId: objection.userId,
  });

  const result = await prisma.$transaction(async (tx) => {
    const updated = await tx.objection.update({
      where: { id: objection.id },
      data: {
        refNumber,
        status: "UNDER_REVIEW",
        submittedAt: new Date(),
      },
    });

    // Consume the editable draft form state, if any survives.
    await tx.objectionDraft.deleteMany({
      where: { userId: objection.userId, lineItemId: objection.lineItemId },
    });

    const notification = await tx.notification.create({
      data: {
        userId: objection.userId,
        objectionId: objection.id,
        type: "OBJECTION_RECEIVED",
        channel: "PUSH",
        status: "PENDING",
      },
    });

    return { objection: updated, notificationId: notification.id };
  });

  // POPIA audit: the objection was submitted to the municipality (ref minted).
  await writeAudit({
    event: "OBJECTION_SUBMITTED",
    userId: objection.userId,
    entityId: objection.id,
    entityType: "Objection",
    metadata: { refNumber },
  });

  // Step 3 (async): fan the confirmation notification out after commit.
  await enqueueNotification({ notificationId: result.notificationId });

  console.log(
    `[queue:objection-submit] submitted objection=${objection.id} ref=${refNumber}`,
  );
  return { objectionId: result.objection.id, refNumber };
}

export function startObjectionSubmitWorker(): Worker<ObjectionSubmitJobData> | null {
  const connection = getQueueConnection();
  if (!connection) {
    console.warn(
      "[queue:objection-submit] Redis unavailable — worker not started.",
    );
    return null;
  }
  const worker = new Worker<ObjectionSubmitJobData>(
    OBJECTION_SUBMIT_QUEUE_NAME,
    async (job: Job<ObjectionSubmitJobData>) => {
      await processObjectionSubmitJob(job.data);
    },
    { connection: connection as unknown as ConnectionOptions },
  );
  worker.on("failed", (job, err) => {
    console.error(
      `[queue:objection-submit] job ${job?.id} failed:`,
      err.message,
    );
  });
  return worker;
}
