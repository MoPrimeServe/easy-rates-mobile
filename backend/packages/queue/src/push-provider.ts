import { resolve, isAbsolute } from "node:path";
import { env } from "@easyrates/config";

/**
 * Push-notification delivery behind one interface, selected by PUSH_DRIVER.
 *
 *  - FcmPushProvider — real FCM via firebase-admin (`admin.messaging().send`).
 *    Selected when a service-account credential is present (PUSH_DRIVER=auto|fcm).
 *  - MockPushProvider — structured-log "send" (the prior MVP behaviour). The
 *    fallback when no credential is configured (PUSH_DRIVER=auto|mock).
 *
 * A push with no device token is a no-op for both (the persisted Notification
 * row is still the source of truth; the push is only a wake-hint).
 */

export interface PushMessage {
  token: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface PushProvider {
  /** Deliver a push. `dryRun` validates auth/project without delivering. */
  send(msg: PushMessage, dryRun?: boolean): Promise<void>;
}

// ---- Mock (structured log) --------------------------------------------------

export class MockPushProvider implements PushProvider {
  async send(msg: PushMessage): Promise<void> {
    console.log(
      `[push:mock] send title="${msg.title}" token=${msg.token ? "present" : "none"}`,
    );
  }
}

// ---- FCM via firebase-admin -------------------------------------------------

/** Minimal slice of firebase-admin messaging used here (keeps the provider
 * injectable / unit-testable with a double). */
export interface FirebaseMessaging {
  send(
    message: {
      token: string;
      notification: { title: string; body: string };
      data?: Record<string, string>;
    },
    dryRun?: boolean,
  ): Promise<string>;
}

export class FcmPushProvider implements PushProvider {
  constructor(private readonly messaging: FirebaseMessaging) {}

  async send(msg: PushMessage, dryRun = false): Promise<void> {
    await this.messaging.send(
      {
        token: msg.token,
        notification: { title: msg.title, body: msg.body },
        ...(msg.data ? { data: msg.data } : {}),
      },
      dryRun,
    );
  }
}

// ---- Selection (env-driven, default-safe) -----------------------------------

let singleton: PushProvider | null = null;

/**
 * Resolve GOOGLE_APPLICATION_CREDENTIALS relative to the backend root. Returns
 * the absolute path, or null when unset.
 */
export function resolveCredentialPath(): string | null {
  const gac = env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!gac) return null;
  return isAbsolute(gac) ? gac : resolve(process.cwd(), gac);
}

/**
 * Build the real firebase-admin messaging surface. Lazily initialises a single
 * firebase app from the service-account JSON. Throws if the credential is unset.
 * Kept async + dynamically imported so firebase-admin is only loaded when used.
 */
export async function createFirebaseMessaging(): Promise<FirebaseMessaging> {
  const credPath = resolveCredentialPath();
  if (!credPath) {
    throw new Error(
      "[push] PUSH_DRIVER=fcm but GOOGLE_APPLICATION_CREDENTIALS is unset.",
    );
  }
  const admin = (await import("firebase-admin")).default;
  if (admin.apps.length === 0) {
    admin.initializeApp({
      credential: admin.credential.cert(credPath),
      ...(env.FCM_PROJECT_ID ? { projectId: env.FCM_PROJECT_ID } : {}),
    });
  }
  return admin.messaging() as unknown as FirebaseMessaging;
}

/**
 * Select the push provider (cached). FCM when a credential is present and
 * PUSH_DRIVER permits; else the mock. Falls back to mock (logged) if FCM init
 * throws, so a misconfigured credential never crashes the worker.
 */
export async function selectPushProvider(): Promise<PushProvider> {
  if (singleton) return singleton;
  const hasCred = Boolean(resolveCredentialPath());
  const useFcm =
    env.PUSH_DRIVER === "fcm" || (env.PUSH_DRIVER === "auto" && hasCred);

  if (useFcm) {
    try {
      const messaging = await createFirebaseMessaging();
      singleton = new FcmPushProvider(messaging);
      console.log(
        `[push] driver: FCM (project=${env.FCM_PROJECT_ID ?? "default"}).`,
      );
      return singleton;
    } catch (e) {
      console.warn(
        "[push] FCM init failed — falling back to mock push:",
        (e as Error).message,
      );
    }
  }
  singleton = new MockPushProvider();
  console.log("[push] driver: mock (structured log).");
  return singleton;
}

/** Reset the cached provider (test isolation). */
export function __resetPushProviderForTests(): void {
  singleton = null;
}
