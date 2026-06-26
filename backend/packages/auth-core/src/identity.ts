import { createHmac } from "node:crypto";
import { z } from "zod";

/** E.164 South African phone: +27 followed by 9 digits. */
export const PHONE_REGEX = /^\+27\d{9}$/;

export const phoneSchema = z
  .string()
  .regex(PHONE_REGEX, "Must be a +27 E.164 number.");

/**
 * Mask a phone for display: "+27821234567" → "+27****1234". Operates on the
 * SUBMITTED value (never a DB lookup) so login stays anti-enumeration safe.
 */
export function maskPhone(phone: string): string {
  if (!PHONE_REGEX.test(phone)) return phone;
  const cc = phone.slice(0, 3); // +27
  const last4 = phone.slice(-4);
  return `${cc}****${last4}`;
}

/**
 * Validate a 13-digit South African ID number (format + Luhn checksum).
 * Returns true iff well-formed and the check digit is correct.
 */
export function isValidSaId(idNumber: string): boolean {
  if (!/^\d{13}$/.test(idNumber)) return false;
  // Luhn over all 13 digits (the 13th is the check digit).
  let sum = 0;
  let double = false;
  for (let i = idNumber.length - 1; i >= 0; i--) {
    let d = idNumber.charCodeAt(i) - 48;
    if (double) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    double = !double;
  }
  return sum % 10 === 0;
}

export const idNumberSchema = z
  .string()
  .refine(isValidSaId, "Must be a valid 13-digit South African ID number.");

/**
 * HMAC-SHA256(pepper, idNumber) → hex. ADR-003: the plaintext SA ID is hashed
 * and discarded within the request; only the hash is ever persisted.
 */
export function hashIdNumber(idNumber: string, pepper: string): string {
  return createHmac("sha256", pepper).update(idNumber).digest("hex");
}
