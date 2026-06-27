import { Queue, Worker, type ConnectionOptions, type Job } from "bullmq";
import { prisma } from "@easyrates/db";
import { getQueueConnection } from "./connection.js";

/**
 * notification queue — the async dispatch path for an already-persisted
 * Notification row (the row is the source of truth; PUSH/SMS/EMAIL are a wake
 * hint, dispatched out-of-band). A producer enqueues the row id; the worker
 * marks it SENT and mock-sends the push.
 *
 * Real FCM/Twilio/Postmark adapters are post-MVP — the worker stubs the send
 * with a structured log so the lifecycle is observable end-to-end.
 */
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

  // Mock push send — real FCM/Twilio/Postmark adapters are post-MVP.
  const token = notification.user.deviceToken;
  console.log(
    `[queue:notification] mock-send ${notification.channel} type=${notification.type} ` +
      `to user=${notification.userId} token=${token ? "present" : "none"}`,
  );

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
