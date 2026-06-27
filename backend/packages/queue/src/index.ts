// Connection + health probe
export {
  getQueueConnection,
  pingQueue,
  closeQueueConnection,
} from "./connection.js";

// Notification dispatch queue
export {
  NOTIFICATION_QUEUE_NAME,
  getNotificationQueue,
  enqueueNotification,
  processNotificationJob,
  startNotificationWorker,
} from "./notification-queue.js";
export type { NotificationJobData } from "./notification-queue.js";

// Push-notification provider (FCM / mock)
export {
  MockPushProvider,
  FcmPushProvider,
  selectPushProvider,
  createFirebaseMessaging,
  resolveCredentialPath,
  __resetPushProviderForTests,
} from "./push-provider.js";
export type {
  PushProvider,
  PushMessage,
  FirebaseMessaging,
} from "./push-provider.js";

// Objection submission queue
export {
  OBJECTION_SUBMIT_QUEUE_NAME,
  getObjectionSubmitQueue,
  enqueueObjectionSubmit,
  processObjectionSubmitJob,
  startObjectionSubmitWorker,
} from "./objection-submit-queue.js";
export type { ObjectionSubmitJobData } from "./objection-submit-queue.js";
