import { describe, it, expect } from "vitest";
import {
  FcmPushProvider,
  MockPushProvider,
  resolveCredentialPath,
  type FirebaseMessaging,
  type PushMessage,
} from "./push-provider.js";

const MSG: PushMessage = {
  token: "device-token-abc",
  title: "Objection received",
  body: "We have logged your objection.",
  data: { notificationId: "n1", type: "OBJECTION_RECEIVED" },
};

/** A firebase-admin messaging double that records the send call + dryRun flag. */
function makeMessaging(opts: { throwErr?: Error } = {}): {
  messaging: FirebaseMessaging;
  calls: { message: unknown; dryRun: boolean | undefined }[];
} {
  const calls: { message: unknown; dryRun: boolean | undefined }[] = [];
  const messaging: FirebaseMessaging = {
    async send(message, dryRun) {
      calls.push({ message, dryRun });
      if (opts.throwErr) throw opts.throwErr;
      return "projects/easyrates/messages/fake-id";
    },
  };
  return { messaging, calls };
}

describe("FcmPushProvider", () => {
  it("maps PushMessage → firebase message shape and forwards dryRun", async () => {
    const { messaging, calls } = makeMessaging();
    const provider = new FcmPushProvider(messaging);
    await provider.send(MSG, true);
    expect(calls).toHaveLength(1);
    expect(calls[0]!.dryRun).toBe(true);
    expect(calls[0]!.message).toMatchObject({
      token: "device-token-abc",
      notification: { title: "Objection received", body: "We have logged your objection." },
      data: { notificationId: "n1", type: "OBJECTION_RECEIVED" },
    });
  });

  it("defaults dryRun to false for a real send", async () => {
    const { messaging, calls } = makeMessaging();
    await new FcmPushProvider(messaging).send(MSG);
    expect(calls[0]!.dryRun).toBe(false);
  });

  it("propagates a messaging error (so the worker can log it)", async () => {
    const { messaging } = makeMessaging({ throwErr: new Error("invalid token") });
    await expect(new FcmPushProvider(messaging).send(MSG)).rejects.toThrow("invalid token");
  });
});

describe("MockPushProvider", () => {
  it("resolves without throwing (structured-log no-op)", async () => {
    await expect(new MockPushProvider().send(MSG)).resolves.toBeUndefined();
  });
});

describe("resolveCredentialPath", () => {
  it("returns an absolute path or null (never a bare relative string)", () => {
    const p = resolveCredentialPath();
    if (p !== null) {
      expect(p.startsWith("/")).toBe(true);
    } else {
      expect(p).toBeNull();
    }
  });
});
