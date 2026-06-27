import type { OtpPurpose, SendResult, ResendResult } from "./otp-state.js";
import { OtpStateMachine } from "./otp-state.js";

/**
 * OtpProvider — the swappable OTP delivery boundary the otp-service routes call
 * (`rt.otp.send / verify / resend`). Two implementations satisfy it:
 *
 *  - MockOtpProvider  — wraps the in-process OtpStateMachine (CSPRNG code, HMAC
 *    hashing, phone-keyed Redis/memory store). Selected when OTP_MOCK=true. The
 *    only mode that returns a `mockCode` and never sends a real SMS.
 *  - TwilioVerifyProvider — delegates the whole code lifecycle to Twilio Verify
 *    (Twilio owns generation, TTL, attempt counting). Selected when OTP_MOCK=false.
 *
 * Both expose the SAME shape so app.ts is provider-agnostic. `verify` returns the
 * resolved `purpose` so the route can branch REGISTRATION vs LOGIN — the Twilio
 * provider tracks purpose in a side key since Twilio Verify itself is purpose-blind.
 */
export interface OtpProvider {
  send(phone: string, purpose: OtpPurpose): Promise<SendResult>;
  verify(phone: string, code: string): Promise<{ purpose: OtpPurpose }>;
  resend(phone: string, purpose: OtpPurpose): Promise<ResendResult>;
}

/** The mock provider is exactly the existing state machine (already implements the shape). */
export class MockOtpProvider implements OtpProvider {
  constructor(private readonly machine: OtpStateMachine) {}

  send(phone: string, purpose: OtpPurpose): Promise<SendResult> {
    return this.machine.send(phone, purpose);
  }
  verify(phone: string, code: string): Promise<{ purpose: OtpPurpose }> {
    return this.machine.verify(phone, code);
  }
  resend(phone: string, purpose: OtpPurpose): Promise<ResendResult> {
    return this.machine.resend(phone, purpose);
  }
}
