import { Queue, Worker, type ConnectionOptions, type Job } from "bullmq";
import { prisma } from "@easyrates/db";
import { getQueueConnection } from "./connection.js";
import { selectPushProvider } from "./push-provider.js";

/**
 * notification queue — the async dispatch path for an already-persisted
 * Notification row (the row is the source of truth; PUSH/SMS/EMAIL are a wake
 * hint, dispatched out-of-band). A producer enqueues the row id; the worker
 * marks it SENT and dispatches the push via the selected PushProvider (real FCM
 * when a credential is present, else a structured-log mock — see push-provider.ts).
 */

/** Server-composed push copy per Notification type (mirrors the inbox COPY). */
const PUSH_COPY: Record<string, { title: string; body: string }> = {
  BILL_ISSUED: { title: "A new bill is available", body: "Your latest municipal bill is ready to view." },
  PAYMENT_DUE: { title: "Payment due soon", body: "A payment deadline on your account is approaching." },
  OBJECTION_STATUS: { title: "Your objection status changed", body: "The municipality has updated your objection." },
  OBJECTION_RECEIVED: { title: "Objection received", body: "We have logged your objection; it is now under review." },
  MORE_INFO_REQUESTED: { title: "More information requested", body: "Additional documents are needed for your objection." },
  KYC_STATUS: { title: "Identity verification update", body: "There is an update on your identity verification." },
};
export const NOTIFICATION_QUEUE_NAME = "notification";

export interface NotificationJobData {
  /** Notification.id of the already-persisted row to dispatch. */
  notificationId: string;
}

let notificationQueueSingleton: Queue<NotificationJobData> | null = null;

/**
 * The notification producer. Returns null when Redis is unavailable so callers
 * degrade gracefully (the Notification row is already persisted; only the async
 * wake-hint is skipped).
 */
export function getNotificationQueue(): Queue<NotificationJobData> | null {
  const connection = getQueueConnection();
  if (!connection) return null;
  if (notificationQueueSingleton) return notificationQueueSingleton;
  notificationQueueSingleton = new Queue(NOTIFICATION_QUEUE_NAME, {
    connection: connection as unknown as ConnectionOptions,
  }) as Queue<NotificationJobData>;
  return notificationQueueSingleton;
}

/**
 * Enqueue a notification dispatch. No-op (returns false) when Redis is down —
 * the persisted row is unaffected; an operator can re-drive later. Returns true
 * when the job was accepted by the broker.
 */
export async function enqueueNotification(
  data: NotificationJobData,
): Promise<boolean> {
  const queue = getNotificationQueue();
  if (!queue) {
    console.warn(
      "[queue:notification] Redis unavailable — notification row persisted, dispatch skipped:",
      data.notificationId,
    );
    return false;
  }
  await queue.add("dispatch", data, {
    removeOnComplete: 1000,
    removeOnFail: 5000,
    attempts: 3,
    backoff: { type: "exponential", delay: 1000 },
  });
  return true;
}

/**
 * Process one notification dispatch: mark the row SENT and mock-send the push.
 * Exported so the worker and unit tests share one code path.
 */
export async function processNotificationJob(
  data: NotificationJobData,
): Promise<void> {
  const notification = await prisma.notification.findUnique({
    where: { id: data.notificationId },
    include: { user: { select: { deviceToken: true } } },
  });
  if (!notification) {
    console.warn(
      "[queue:notification] no Notification row for id:",
      data.notificationId,
    );
    return;
  }

  // Dispatch the push via the selected provider (FCM or mock). Only PUSH-channel
  // rows with a device token get a real push; the persisted row is authoritative
  // regardless, so a missing token / push failure must not fail the job.
  const token = notification.user.deviceToken;
  if (notification.channel === "PUSH" && token) {
    const copy = PUSH_COPY[notification.type] ?? {
      title: "Notification",
      body: "You have a new notification.",
    };
    try {
      const push = await selectPushProvider();
      await push.send({
        token,
        title: copy.title,
        body: copy.body,
        data: { notificationId: notification.id, type: notification.type },
      });
    } catch (e) {
      // Push is a wake-hint — log and continue; the row still flips to SENT.
      console.warn(
        `[queue:notification] push dispatch failed for ${notification.id}:`,
        (e as Error).message,
      );
    }
  } else {
    console.log(
      `[queue:notification] no push (channel=${notification.channel} token=${token ? "present" : "none"}) ` +
        `type=${notification.type} user=${notification.userId}`,
    );
  }

  // The persisted row is the source of truth — flip it to SENT (dispatched).
  await prisma.notification.update({
    where: { id: notification.id },
    data: { status: "SENT", sentAt: new Date() },
  });
}

/**
 * Start the notification worker. Returns null when Redis is unavailable.
 * Caller owns the returned Worker's lifecycle (await worker.close()).
 */
export function startNotificationWorker(): Worker<NotificationJobData> | null {
  const connection = getQueueConnection();
  if (!connection) {
    console.warn(
      "[queue:notification] Redis unavailable — worker not started.",
    );
    return null;
  }
  const worker = new Worker<NotificationJobData>(
    NOTIFICATION_QUEUE_NAME,
    async (job: Job<NotificationJobData>) => {
      await processNotificationJob(job.data);
    },
    { connection: connection as unknown as ConnectionOptions },
  );
  worker.on("failed", (job, err) => {
    console.error(
      `[queue:notification] job ${job?.id} failed:`,
      err.message,
    );
  });
  return worker;
}
