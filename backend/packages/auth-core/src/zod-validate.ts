import { ApiError } from "@easyrates/http";
import type { ZodTypeAny, z } from "zod";

/**
 * Parse `body` against `schema`, or throw ApiError.validation with the
 * conventions §4 `details.fields` shape (field path → first message, dot-joined
 * for nested paths). One place so every route paints inline errors identically.
 *
 * Returns the schema's OUTPUT type (`z.infer`), so `.default()` / `.transform()`
 * fields are correctly non-optional at the call site (a draft/list query with
 * `page: z.coerce.number().default(1)` yields `page: number`, not `number?`).
 */
export function parseOrValidationError<S extends ZodTypeAny>(
  schema: S,
  body: unknown,
): z.infer<S> {
  const result = schema.safeParse(body);
  if (result.success) return result.data;

  const fields: Record<string, string> = {};
  for (const issue of result.error.issues) {
    const path = issue.path.join(".") || "(root)";
    if (!(path in fields)) fields[path] = issue.message; // first message wins
  }
  throw ApiError.validation(fields);
}
