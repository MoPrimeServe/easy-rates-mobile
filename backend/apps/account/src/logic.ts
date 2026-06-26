/**
 * account-service.md "TypeScript interfaces". `data` payloads only.
 */
export interface AccountProfileResponse {
  userId: string;
  displayName: string;
  email: string;
  phoneMasked: string;
  idNumberMasked: string;
}

export type AccountStatus = "ACTIVE" | "INACTIVE" | "ARCHIVED";

export interface LinkedPropertyResponse {
  id: string;
  accountNumber: string;
  address: string;
  erfNumber: string | null;
  ward: string;
  status: AccountStatus;
  linkedAt: string;
}

export type PreferenceLanguage = "en" | "zu" | "af" | "st";

export interface AccountPreferencesResponse {
  smsEnabled: boolean;
  pushEnabled: boolean;
  emailEnabled: boolean;
  language: PreferenceLanguage;
}

/**
 * Mask an E.164 SA phone for display, e.g. "+27821234567" → "+27 82 XXX X567"
 * (account-service.md profile shape). Operates on the stored value; never
 * reveals the middle digits.
 */
export function maskPhoneDisplay(phone: string | null): string {
  if (!phone) return "";
  const m = /^\+27(\d{2})(\d{3})(\d{4})$/.exec(phone);
  if (!m) return phone;
  const [, area, , last4] = m;
  return `+27 ${area} XXX X${last4!.slice(1)}`;
}

/**
 * Masked SA ID number for display. ADR-003: the plaintext SA ID is never
 * stored — only `idNumberHash`. We therefore cannot reveal real leading/trailing
 * ID digits; we emit a fixed-shape masked placeholder ("•" body, 13 chars) so
 * the Profile Settings screen renders, without inventing real digits.
 */
export function maskIdNumberDisplay(idNumberHash: string | null): string {
  if (!idNumberHash) return "";
  // 13-digit SA ID shape, fully masked (no plaintext available to reveal).
  return "•••••••••••••";
}
