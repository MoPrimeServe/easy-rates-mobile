import { config as loadDotenv } from "dotenv";
import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { z } from "zod";

/**
 * Zod-validated environment module. Fails fast (process.exit(1)) with a readable,
 * non-stack-trace message naming the offending variable(s). Import the named
 * `env` from `@easyrates/config` at every service entry point — never read
 * `process.env` directly in handlers.
 */

/**
 * Locate the monorepo-root `.env` by walking up from cwd until a directory
 * containing `pnpm-workspace.yaml` (the backend root) is found. This makes env
 * loading robust whether the process starts from the backend root (services via
 * tsx) or a package directory (vitest runs with cwd = the package). Returns the
 * resolved `.env` path, or undefined to let dotenv fall back to cwd.
 */
function findRootEnv(): string | undefined {
  let dir = process.cwd();
  for (let i = 0; i < 8; i += 1) {
    if (existsSync(resolve(dir, "pnpm-workspace.yaml"))) {
      return resolve(dir, ".env");
    }
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return undefined;
}

// Load .env from the backend root (monorepo root). dotenv is a no-op for vars
// already set (e.g. injected by the container runtime).
loadDotenv({ path: findRootEnv() });

const portSchema = z.coerce.number().int().positive().max(65535);

const envSchema = z.object({
  // Runtime
  NODE_ENV: z
    .enum(["development", "test", "production"])
    .default("development"),
  PORT: portSchema.default(3000),
  ALLOWED_ORIGINS: z.string().min(1).default("http://localhost:3000"),

  // Database (Prisma)
  DATABASE_URL: z.string().min(1, "DATABASE_URL is required"),

  // Redis / BullMQ. Optional locally: queue degrades gracefully if absent.
  REDIS_URL: z.string().min(1).optional(),

  // JWT (auth-service)
  JWT_SECRET: z.string().min(1, "JWT_SECRET is required"),
  JWT_REFRESH_SECRET: z.string().min(1, "JWT_REFRESH_SECRET is required"),
  JWT_ACCESS_TTL_SECONDS: z.coerce.number().int().positive().default(900),
  JWT_REFRESH_TTL_DAYS: z.coerce.number().int().positive().default(30),

  // RS256 keypair for access tokens (conventions §6). Supply EITHER the PEM
  // contents inline (…_PEM) OR a filesystem path to the PEM (…_PEM_PATH).
  // The private key signs; the public key verifies. Dev keys live under
  // backend/keys/ (private key gitignored).
  JWT_PRIVATE_KEY_PEM: z.string().optional(),
  JWT_PUBLIC_KEY_PEM: z.string().optional(),
  JWT_PRIVATE_KEY_PEM_PATH: z
    .string()
    .default("./keys/jwt-rs256-private.pem"),
  JWT_PUBLIC_KEY_PEM_PATH: z.string().default("./keys/jwt-rs256-public.pem"),
  JWT_ISSUER: z.string().default("easyrates-auth"),
  JWT_AUDIENCE: z.string().default("easyrates-api"),

  // OTP lifecycle params (otp-service contract — central resolved values).
  OTP_TTL_SECONDS: z.coerce.number().int().positive().default(600),
  OTP_RESEND_COOLDOWN_SECONDS: z.coerce.number().int().positive().default(30),
  OTP_MAX_RESENDS_PER_SESSION: z.coerce.number().int().positive().default(3),
  OTP_MAX_INVALID_ATTEMPTS: z.coerce.number().int().positive().default(5),

  // OTP delivery adapter. OTP_MOCK=true → generate + log/return the code in dev
  // (the only mode without real Twilio). In production OTP_MOCK MUST be false.
  OTP_MOCK: z
    .enum(["true", "false"])
    .default("true")
    .transform((v) => v === "true"),

  // Registration proof token TTL (single-use, minted by otp/verify REGISTRATION).
  REGISTRATION_TOKEN_TTL_SECONDS: z.coerce
    .number()
    .int()
    .positive()
    .default(600),

  // Server-to-server shared secret guarding otp-service POST /otp/send [internal].
  INTERNAL_API_SECRET: z
    .string()
    .min(1)
    .default("dev-only-internal-s2s-secret-change-me"),

  // Service base URLs for cross-service calls (auth → otp).
  OTP_SERVICE_URL: z.string().default("http://localhost:3002"),

  // ADR-003 ID-number HMAC pepper
  ID_NUMBER_HMAC_PEPPER: z
    .string()
    .min(1, "ID_NUMBER_HMAC_PEPPER is required"),

  // Twilio Verify (OTP delivery) — optional locally (TWILIO can be mocked)
  TWILIO_ACCOUNT_SID: z.string().optional(),
  TWILIO_AUTH_TOKEN: z.string().optional(),
  TWILIO_SERVICE_SID: z.string().optional(),

  // Municipality inbound webhook shared secret
  MUNICIPAL_WEBHOOK_SECRET: z
    .string()
    .min(1, "MUNICIPAL_WEBHOOK_SECRET is required"),

  // Local blob-storage stub directory (objection evidence). Azure Blob Storage
  // is the production target — this is the dev stub. Gitignored.
  BLOB_DIR: z.string().min(1).default("./blob-store"),

  // ---- Azure Blob Storage (objection evidence — prod target) ---------------
  // Connection string for the `easyrates` storage account. When present (and
  // BLOB_DRIVER is "auto" or "azure") the AzureBlobStore is selected; otherwise
  // the local filesystem stub (BLOB_DIR) is used.
  AZURE_STORAGE_CONNECTION_STRING: z.string().optional(),
  AZURE_BLOB_CONTAINER: z.string().min(1).default("evidence"),
  // Evidence blob backend selector. "auto" (default): azure iff a connection
  // string is present, else local. "azure"/"local" force the choice.
  BLOB_DRIVER: z.enum(["auto", "azure", "local"]).default("auto"),

  // ---- FCM (push notifications) --------------------------------------------
  // Service-account credential for firebase-admin. Path is resolved relative to
  // the backend root. FCM_PROJECT_ID pins the project for the dry-run check.
  GOOGLE_APPLICATION_CREDENTIALS: z.string().optional(),
  FCM_PROJECT_ID: z.string().optional(),
  // Push backend selector. "auto" (default): fcm iff a credential is present,
  // else the mock (structured-log) push. "fcm"/"mock" force the choice.
  PUSH_DRIVER: z.enum(["auto", "fcm", "mock"]).default("auto"),

  // ---- Rate limiting (conventions §5; Redis-backed) ------------------------
  // Master toggle. Default true; set false to disable all limiters (e.g. tests).
  // Falls back to a fail-open in-memory counter when Redis is unavailable.
  RATE_LIMIT_ENABLED: z
    .enum(["true", "false"])
    .default("true")
    .transform((v) => v === "true"),
});

export type Env = z.infer<typeof envSchema>;

function parseEnv(): Env {
  const parsed = envSchema.safeParse(process.env);
  if (!parsed.success) {
    const lines = parsed.error.issues.map(
      (issue) =>
        `  - ${issue.path.join(".") || "(root)"}: ${issue.message}`,
    );
    // Readable message, NOT a stack trace.
    console.error(
      `[config] Invalid or missing environment variables:\n${lines.join("\n")}`,
    );
    process.exit(1);
  }
  // JWT_SECRET and JWT_REFRESH_SECRET must differ (ADR-001 §D).
  if (parsed.data.JWT_SECRET === parsed.data.JWT_REFRESH_SECRET) {
    console.error(
      "[config] JWT_SECRET and JWT_REFRESH_SECRET must differ (ADR-001 §D).",
    );
    process.exit(1);
  }
  return parsed.data;
}

export const env: Env = parseEnv();
