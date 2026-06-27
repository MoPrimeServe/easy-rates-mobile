import type {
  Notification,
  NotificationChannel,
  NotificationStatus,
  NotificationType,
} from "@easyrates/db";

/**
 * notification-service business logic — pure mappers + server-composed inbox
 * strings (the Notification row has no title/preview column; the contract's
 * `title`/`preview` are render-ready strings composed per `type` here).
 */

export interface NotificationInboxItem {
  id: string;
  type: NotificationType;
  channel: NotificationChannel;
  status: NotificationStatus;
  objectionRef: string | null;
  title: string;
  preview: string;
  sentAt: string;
  read: boolean;
}

const COPY: Record<NotificationType, { title: string; preview: string }> = {
  BILL_ISSUED: {
    title: "A new bill is available",
    preview: "Your latest municipal bill is ready to view.",
  },
  PAYMENT_DUE: {
    title: "Payment due soon",
    preview: "A payment deadline on your account is approaching.",
  },
  OBJECTION_STATUS: {
    title: "Your objection status changed",
    preview: "The municipality has updated the status of your objection.",
  },
  OBJECTION_RECEIVED: {
    title: "Objection received",
    preview: "We have logged your objection and it is now under review.",
  },
  MORE_INFO_REQUESTED: {
    title: "More information requested",
    preview: "The municipality has requested additional documents for your objection.",
  },
  KYC_STATUS: {
    title: "Identity verification update",
    preview: "There is an update on your identity verification.",
  },
};

/**
 * The Prisma `where` for the inbox list. `unreadOnly` adds `readAt: null`.
 * Pure so the unreadOnly filter is unit-testable without a DB.
 */
export function inboxWhere(userId: string, unreadOnly: boolean): {
  userId: string;
  readAt?: null;
} {
  return unreadOnly ? { userId, readAt: null } : { userId };
}

/**
 * `read-all` flips only the caller's UNREAD rows; the `updatedCount` is the
 * number actually flipped (already-read rows are not re-counted). This helper
 * captures that count semantics from an in-memory row set, so the count
 * contract is testable without a DB.
 */
export function countUnread(
  rows: Pick<Notification, "readAt">[],
): number {
  return rows.filter((r) => r.readAt == null).length;
}

/** `read` is derived: a row is read iff `readAt` is non-null (data-model gap #2 resolved). */
export function isRead(n: Pick<Notification, "readAt">): boolean {
  return n.readAt != null;
}

export function toInboxItem(
  n: Pick<
    Notification,
    "id" | "type" | "channel" | "status" | "sentAt" | "readAt"
  >,
  objectionRef: string | null,
): NotificationInboxItem {
  const copy = COPY[n.type] ?? { title: "Notification", preview: "" };
  return {
    id: n.id,
    type: n.type,
    channel: n.channel,
    status: n.status,
    objectionRef,
    title: copy.title,
    preview: copy.preview,
    sentAt: n.sentAt.toISOString(),
    read: isRead(n),
  };
}
