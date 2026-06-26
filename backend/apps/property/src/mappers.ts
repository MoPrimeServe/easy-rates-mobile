import type { Property } from "@easyrates/db";

/**
 * property-service contract data shapes (system-design/api/property-service.md
 * "TypeScript interfaces"). These are the `data` payloads — the envelope wraps
 * them on the wire.
 */
export interface PropertySummaryResponse {
  id: string;
  accountNumber: string;
  ownerName: string | null;
  address: string;
  erfNumber: string | null;
  ward: string;
}

export interface PropertyDetailResponse {
  id: string;
  accountNumber: string;
  ownerName: string | null;
  address: string;
  erfNumber: string | null;
  ward: string;
  extentSqm: number;
  municipalValue: string; // money — decimal string, ZAR, 2 dp (conventions §9)
  dataAsOf: string; // ISO 8601 datetime (UTC)
}

/**
 * `ward`, `extentSqm`, `municipalValue`, and `dataAsOf` are not first-class
 * columns on Property — they live in the `metadata` JSON synced from the
 * billing system (data-model/property-account.md: "raw fields from the
 * municipality billing system sync"). Read them defensively.
 */
function meta(p: Property): Record<string, unknown> {
  return (p.metadata as Record<string, unknown> | null) ?? {};
}

export function ward(p: Property): string {
  const w = meta(p)["ward"];
  return typeof w === "string" ? w : "";
}

/**
 * The identity gate (ADR-003): a property is visible to the user iff the user's
 * keyed ID hash appears in the property's holder hashes. Hash-to-hash; no
 * plaintext ID ever crosses this boundary.
 */
export function passesIdentityGate(
  userIdNumberHash: string | null,
  holderIdNumberHashes: string[],
): boolean {
  if (!userIdNumberHash) return false;
  return holderIdNumberHashes.includes(userIdNumberHash);
}

export function toSummary(p: Property): PropertySummaryResponse {
  return {
    id: p.id,
    accountNumber: p.accountNumber,
    ownerName: p.ownerName,
    address: p.address,
    erfNumber: p.erfNumber,
    ward: ward(p),
  };
}

function asMoney(v: unknown): string {
  // Decimal string with 2 fraction digits (conventions §9).
  if (typeof v === "number") return v.toFixed(2);
  if (typeof v === "string" && v.trim() !== "" && !Number.isNaN(Number(v))) {
    return Number(v).toFixed(2);
  }
  return "0.00";
}

export function toDetail(p: Property): PropertyDetailResponse {
  const m = meta(p);
  const extent = m["extentSqm"];
  const dataAsOf = m["dataAsOf"];
  return {
    id: p.id,
    accountNumber: p.accountNumber,
    ownerName: p.ownerName,
    address: p.address,
    erfNumber: p.erfNumber,
    ward: ward(p),
    extentSqm: typeof extent === "number" ? extent : 0,
    municipalValue: asMoney(m["municipalValue"]),
    dataAsOf:
      typeof dataAsOf === "string"
        ? dataAsOf
        : new Date(0).toISOString(),
  };
}
