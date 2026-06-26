import { config as loadDotenv } from "dotenv";
import { z } from "zod";

/**
 * Zod-validated environment module. Fails fast (process.exit(1)) with a readable,
 * non-stack-trace message naming the offending variable(s). Import the named
 * `env` from `@easyrates/config` at every service entry point — never read
 * `process.env` directly in handlers.
 */

// Load .env from the backend root (monorepo root). dotenv is a no-op if vars
// are already set (e.g. injected by the container runtime).
loadDotenv();

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
