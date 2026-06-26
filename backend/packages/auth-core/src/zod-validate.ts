import { ApiError } from "@easyrates/http";
import type { ZodSchema } from "zod";

/**
 * Parse `body` against `schema`, or throw ApiError.validation with the
 * conventions §4 `details.fields` shape (field path → first message, dot-joined
 * for nested paths). One place so every route paints inline errors identically.
 */
export function parseOrValidationError<T>(schema: ZodSchema<T>, body: unknown): T {
  const result = schema.safeParse(body);
  if (result.success) return result.data;

  const fields: Record<string, string> = {};
  for (const issue of result.error.issues) {
    const path = issue.path.join(".") || "(root)";
    if (!(path in fields)) fields[path] = issue.message; // first message wins
  }
  throw ApiError.validation(fields);
}
