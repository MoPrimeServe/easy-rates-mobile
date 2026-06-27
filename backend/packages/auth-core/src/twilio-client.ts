import twilio from "twilio";
import type { TwilioVerifyApi } from "./twilio-verify.js";

/**
 * Constructs the live Twilio Verify API surface bound to one Verify Service SID.
 * Isolated from TwilioVerifyProvider so the provider stays unit-testable with a
 * plain double and never imports the SDK.
 */
export interface TwilioCreds {
  accountSid: string;
  authToken: string;
  serviceSid: string;
}

export function createTwilioVerifyApi(creds: TwilioCreds): TwilioVerifyApi {
  const client = twilio(creds.accountSid, creds.authToken);
  const service = () => client.verify.v2.services(creds.serviceSid);
  return {
    verifications: {
      create: (args) =>
        service().verifications.create({ to: args.to, channel: args.channel }),
    },
    verificationChecks: {
      create: (args) =>
        service().verificationChecks.create({ to: args.to, code: args.code }),
    },
  };
}

/**
 * Credential proof WITHOUT sending an SMS: fetch the Verify Service resource.
 * Returns the service `sid` and `friendlyName` (no secrets). Used by the live
 * smoke to confirm the creds/SID are valid at ~no cost.
 */
export async function fetchVerifyService(
  creds: TwilioCreds,
): Promise<{ sid: string; friendlyName: string }> {
  const client = twilio(creds.accountSid, creds.authToken);
  const svc = await client.verify.v2.services(creds.serviceSid).fetch();
  return { sid: svc.sid, friendlyName: svc.friendlyName };
}
