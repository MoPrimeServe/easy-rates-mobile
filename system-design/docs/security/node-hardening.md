# EasyRates — Node.js Production Hardening

**Status:** Decided  
**Date:** 2026-06-20  
**Downstream:**
- `backend/plans/01-scaffold.md` T2 — `shared/env.ts` Zod schema must match the variable
  list in Checklist C below. **Supersedes** the `JWT_SECRET`/`JWT_REFRESH_SECRET` schema
  in that plan: those variables are **not used** — RS256 with Azure Key Vault is the
  algorithm (sessions.md Decision A). See note in Checklist C.
- `backend/plans/03-auth-service.md` — auth-service wires `trust proxy`, helmet, CORS,
  and the error handler before any route handler.
- All services inherit `shared/app.ts` and `shared/env.ts`.

**OWASP references:** M4 (body size limit), M5 (HTTPS), M8 (misconfiguration), M9
(data storage) — see `docs/security/owasp.md`.

---

## Checklist summary

| # | Item | Status | Reference |
|---|---|---|---|
| A | `helmet.js` security headers | **PASS** | `shared/app.ts`, this doc |
| B | HTTPS enforcement (no plain HTTP in production) | **PASS** | Azure App Service + `trust proxy` |
| C | Startup env validation with Zod (crash-fast) | **PASS** | `shared/env.ts`, this doc |
| D | No secrets in code or committed files | **PASS** | `.gitignore` + `.env.example` convention |
| E | CORS locked to known origins | **PASS** | `ALLOWED_ORIGINS` env var |
| F | `NODE_ENV=production` set in deployment | **PASS** | Azure App Service Application Settings |
| G | Error response sanitization (no stack traces) | **PASS** | `shared/errorHandler.ts`, this doc |
| H | `trust proxy` — required for IP-based rate limiting | **PASS** | `app.set('trust proxy', 1)` |
| I | JSON body size limit (`express.json`) | **PASS** | `express.json({ limit: '64kb' })` |
| J | CSP headers — API server decision | **ACCEPT** | No HTML served; see justification |

**10 items: 9 Pass · 1 Accept · 0 Mitigate · 0 Blank**

---

## Checklist A — helmet.js security headers | PASS

### Configuration

```typescript
// shared/app.ts
import helmet from 'helmet'

app.use(helmet({
  // ── Disabled: not applicable to an API server ────────────────────────────

  // Content-Security-Policy: DISABLED
  // This server returns JSON only (no HTML). CSP headers on JSON responses
  // have no effect in any browser and are ignored by the Flutter native client.
  // Re-enable if a browser-rendered endpoint or admin WebView is ever added.
  contentSecurityPolicy: false,

  // Cross-Origin-Embedder-Policy: DISABLED
  // Only relevant in browser contexts requiring SharedArrayBuffer isolation.
  // No browser-rendered content is served.
  crossOriginEmbedderPolicy: false,

  // ── Overrides from helmet defaults ──────────────────────────────────────

  // Upgrade HSTS from helmet default (15552000 = 180 days) to 1 year + preload
  hsts: {
    maxAge: 31_536_000,       // 1 year in seconds
    includeSubDomains: true,
    preload: true,
  },

  // Upgrade frameguard from default SAMEORIGIN to DENY — no embedding use case
  frameguard: { action: 'deny' },

  // ── All other helmet defaults: ENABLED ───────────────────────────────────
  // X-Content-Type-Options: nosniff
  // X-XSS-Protection: 0            (disables browser's broken XSS auditor)
  // Referrer-Policy: no-referrer
  // X-Permitted-Cross-Domain-Policies: none
  // X-Download-Options: noopen
  // Cross-Origin-Opener-Policy: same-origin
  // Cross-Origin-Resource-Policy: same-origin  (see CORS config for override)
  // Origin-Agent-Cluster: ?1
}))
```

### Headers produced on every response

```
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 0
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
Referrer-Policy: no-referrer
X-Permitted-Cross-Domain-Policies: none
X-Download-Options: noopen
Cross-Origin-Opener-Policy: same-origin
Origin-Agent-Cluster: ?1
```

### CSP decision (Checklist J)

`Content-Security-Policy` is **disabled**. Justification documented in Checklist J.

---

## Checklist B — HTTPS enforcement | PASS

### Architecture

TLS termination is handled by **Azure App Service**, not by the Node.js process.

```
Flutter client ──HTTPS──▶ Azure App Service ingress (TLS 1.2+) ──HTTP──▶ Node.js process
```

Node.js services run on internal HTTP. They are never exposed on a public port.

### Azure configuration (required before deployment)

| Setting | Value | How to set |
|---|---|---|
| HTTPS Only | Enabled | Azure Portal → App Service → TLS/SSL Settings → HTTPS Only: On |
| Minimum TLS Version | TLS 1.2 | Azure Portal → App Service → TLS/SSL Settings → Minimum TLS Version: 1.2 |
| HTTP → HTTPS redirect | Automatic when HTTPS Only is enabled | (no additional config) |
| Public HTTP port | Not exposed | Node.js binds to `PORT` on the internal container network only |

### Node.js side: `trust proxy` (also Checklist H)

```typescript
// shared/app.ts — MUST be first, before all middleware
app.set('trust proxy', 1)
```

This tells Express to trust the `X-Forwarded-Proto` header from Azure's one-hop reverse
proxy. Without it:

- `req.secure` returns `false` even when the client connection is HTTPS
- `req.ip` returns the Azure load balancer's internal IP, not the client's IP
- All IP-based rate limiters (`authLimiter`, `refreshLimiter`) scope to one shared IP —
  effectively disabled

**This is the highest-impact single-line configuration in the hardening checklist.**
Rate limiting is broken if this line is missing.

### HSTS (enforced by helmet Checklist A)

`Strict-Transport-Security: max-age=31536000; includeSubDomains; preload` is set by
helmet on every response. After the first successful HTTPS response, any browser (or
browser-based client) that encounters the domain over HTTP will refuse to connect.

---

## Checklist C — Startup env validation with Zod | PASS

### Principle

Every required environment variable is validated at startup, before any route handler
is wired, before any database connection is opened. If any required variable is missing
or fails format validation, the process prints a readable error and exits with code 1.

**No partial startup.** A service that starts without `DATABASE_URL` is not safer than
one that crashes — it is more dangerous, because it appears healthy until the first
database call, at which point it fails with an opaque error that may leak configuration
state in the stack trace.

### Important: JWT variable correction

`backend/plans/01-scaffold.md` T2 lists `JWT_SECRET` and `JWT_REFRESH_SECRET` as
required variables. **These variables are not used.** The RS256 decision (sessions.md
Decision A) uses Azure Key Vault for signing — there is no HMAC secret. The Zod schema
in `shared/env.ts` supersedes plan/01's variable list. Update plan/01 T2 to reference
this document instead of redefining the schema.

### Zod schema: `shared/env.ts`

```typescript
// shared/env.ts
// IMPORT THIS FILE FIRST in every service entry point.
// It crashes the process before anything else can start if env is incomplete.
import { z } from 'zod'

const envSchema = z.object({

  // ── Runtime ───────────────────────────────────────────────────────────────
  NODE_ENV: z.enum(['production', 'development', 'test'], {
    errorMap: () => ({ message: "NODE_ENV must be 'production', 'development', or 'test'" }),
  }),

  PORT: z
    .string()
    .regex(/^\d{4,5}$/, 'PORT must be a 4- or 5-digit number')
    .transform(Number)
    .default('3000'),

  // ── Database ──────────────────────────────────────────────────────────────
  DATABASE_URL: z.string().url('DATABASE_URL must be a valid connection string URL'),

  // ── Cache ─────────────────────────────────────────────────────────────────
  REDIS_URL: z.string().url('REDIS_URL must be a valid Redis URL (rediss:// for TLS)'),

  // ── JWT (RS256 — NO JWT_SECRET or JWT_REFRESH_SECRET) ────────────────────
  // auth-service uses Azure Key Vault to sign tokens (JWT_SIGNING_KEY_ID + KEY_VAULT_URL).
  // All other services verify via JWKS endpoint (AUTH_SERVICE_JWKS_URL).
  // JWT_SECRET and JWT_REFRESH_SECRET are NOT part of this schema.
  JWT_SIGNING_KEY_ID: z.string().min(1).optional(),    // auth-service only
  KEY_VAULT_URL:      z.string().url().optional(),      // auth-service only
  AUTH_SERVICE_JWKS_URL: z.string().url().optional(),   // all services except auth-service

  ACCESS_TOKEN_TTL_SECONDS: z
    .string()
    .regex(/^\d+$/)
    .transform(Number)
    .default('900'),

  JWKS_CACHE_TTL_MS: z
    .string()
    .regex(/^\d+$/)
    .transform(Number)
    .default('300000'),

  // ── CORS ─────────────────────────────────────────────────────────────────
  ALLOWED_ORIGINS: z
    .string()
    .min(1, 'ALLOWED_ORIGINS must not be empty; use comma-separated URLs for multiple origins'),

  // ── Twilio (otp-service only) ─────────────────────────────────────────────
  TWILIO_ACCOUNT_SID:        z.string().regex(/^AC[0-9a-f]{32}$/).optional(),
  TWILIO_AUTH_TOKEN:         z.string().min(32).optional(),
  TWILIO_VERIFY_SERVICE_SID: z.string().regex(/^VA[0-9a-f]{32}$/).optional(),
  OTP_TTL_SECONDS:           z.string().regex(/^\d+$/).transform(Number).default('600'),
  TWILIO_MOCK: z
    .enum(['true', 'false'])
    .default('false')
    .transform(v => v === 'true'),

  // ── Azure Blob Storage (objection-service only) ───────────────────────────
  AZURE_STORAGE_ACCOUNT_NAME: z.string().min(1).optional(),
  AZURE_STORAGE_ACCOUNT_KEY:  z.string().min(1).optional(),
  AZURE_STORAGE_CONTAINER:    z.string().min(1).optional(),

})

const result = envSchema.safeParse(process.env)

if (!result.success) {
  const issues = result.error.issues
    .map(i => `  ${i.path.join('.')}: ${i.message}`)
    .join('\n')
  // eslint-disable-next-line no-console
  console.error(`[config] Environment validation failed:\n${issues}\nExiting.`)
  process.exit(1)
}

export const env = result.data
export type Env = typeof env
```

### Service-level additional guards

Optional variables are marked `.optional()` in the shared schema above. Each service
adds a startup guard for the vars it specifically requires:

```typescript
// services/auth-service/index.ts
import './../../shared/env'  // shared schema — crashes if NODE_ENV, DATABASE_URL, etc. missing
import { env } from '../../shared/env'

// auth-service-specific required vars
if (!env.JWT_SIGNING_KEY_ID || !env.KEY_VAULT_URL) {
  console.error('[config] auth-service requires JWT_SIGNING_KEY_ID and KEY_VAULT_URL')
  process.exit(1)
}

// services/otp-service/index.ts
if (!env.TWILIO_ACCOUNT_SID || !env.TWILIO_AUTH_TOKEN || !env.TWILIO_VERIFY_SERVICE_SID) {
  if (!env.TWILIO_MOCK) {
    console.error('[config] otp-service requires TWILIO_* vars unless TWILIO_MOCK=true')
    process.exit(1)
  }
}

// services/objection-service/index.ts
if (!env.AZURE_STORAGE_ACCOUNT_NAME || !env.AZURE_STORAGE_ACCOUNT_KEY || !env.AZURE_STORAGE_CONTAINER) {
  console.error('[config] objection-service requires AZURE_STORAGE_* vars')
  process.exit(1)
}
```

### `.env.example` (committed to VCS)

Every variable in the schema must appear in `.env.example` with a comment and a
non-sensitive placeholder value. This is the canonical list of runtime configuration.

```bash
# EasyRates — Environment Variables
# Copy to .env for local development. .env is gitignored — never commit it.
# Production values are set in Azure App Service Application Settings.

# ── Runtime ───────────────────────────────────────────────────────────────────
NODE_ENV=development
PORT=3000

# ── Database ──────────────────────────────────────────────────────────────────
# Azure SQL (production) or local PostgreSQL (development)
DATABASE_URL=postgresql://easyrates:password@localhost:5432/easyrates

# ── Cache / queues ────────────────────────────────────────────────────────────
# Azure Cache for Redis (production) or local Redis (development)
REDIS_URL=redis://localhost:6379

# ── JWT — RS256, Azure Key Vault ──────────────────────────────────────────────
# NOTE: JWT_SECRET and JWT_REFRESH_SECRET are NOT used. RS256 signing key is in
# Azure Key Vault. See system-design/docs/security/sessions.md Decision A.
JWT_SIGNING_KEY_ID=easyrates-jwt-signing-key-2026-06      # auth-service only
KEY_VAULT_URL=https://easyrates-kv.vault.azure.net/        # auth-service only
AUTH_SERVICE_JWKS_URL=http://auth-service:3001/auth/.well-known/jwks.json  # all other services
ACCESS_TOKEN_TTL_SECONDS=900
JWKS_CACHE_TTL_MS=300000

# ── CORS ──────────────────────────────────────────────────────────────────────
# Comma-separated list of allowed browser origins (not needed for Flutter native client)
ALLOWED_ORIGINS=https://easyrates.co.za,https://admin.easyrates.co.za

# ── Twilio OTP ─────────────────────────────────────────────────────────────────
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx         # otp-service only
TWILIO_AUTH_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx            # otp-service only
TWILIO_VERIFY_SERVICE_SID=VAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx  # otp-service only
OTP_TTL_SECONDS=600
TWILIO_MOCK=true   # Set false in production to use real Twilio Verify

# ── Azure Blob Storage ─────────────────────────────────────────────────────────
AZURE_STORAGE_ACCOUNT_NAME=easyrates                          # objection-service only
AZURE_STORAGE_ACCOUNT_KEY=base64encodedkeyhere==              # objection-service only
AZURE_STORAGE_CONTAINER=evidence-uploads                      # objection-service only
```

---

## Checklist D — No secrets in code or committed files | PASS

### `.gitignore` must include

```gitignore
# Environment configuration — never commit
.env
.env.local
.env.*.local

# Generated secret material
*.pem
*.key
*.p12
*.pfx

# Azure credential files
azureauth.json
.azure/
```

### Pre-commit enforcement (strongly recommended)

Add a `pre-commit` hook or `git-secrets` to block commits containing patterns that look
like credentials:

```bash
# .husky/pre-commit (or .git/hooks/pre-commit)
#!/bin/sh
# Fail the commit if any staged file contains suspicious patterns
git diff --cached --name-only | xargs grep -l \
  "AZURE_STORAGE_ACCOUNT_KEY\|TWILIO_AUTH_TOKEN\|-----BEGIN RSA PRIVATE KEY-----" \
  2>/dev/null && {
  echo "[git-secrets] Possible credential found in staged files. Commit blocked."
  exit 1
}
exit 0
```

Or use `secretlint` / `gitleaks` as a more comprehensive alternative.

### Production secrets

All production secrets are stored in **Azure App Service Application Settings**, not in
files:

| Secret | Location |
|---|---|
| `DATABASE_URL` | Azure App Service Application Settings (encrypted at rest) |
| `REDIS_URL` | Azure App Service Application Settings |
| `JWT_SIGNING_KEY_ID` | Azure App Service Application Settings (value is non-secret — it's a key ID, not the key) |
| Azure Key Vault URL | Azure App Service Application Settings |
| `TWILIO_AUTH_TOKEN` | Azure App Service Application Settings |
| `AZURE_STORAGE_ACCOUNT_KEY` | Azure App Service Application Settings or Azure Key Vault reference |
| RSA private key | Azure Key Vault (never leaves Key Vault — used via `sign` API) |

---

## Checklist E — CORS locked to known origins | PASS

### Context

The primary client is the Flutter mobile app. **Flutter is not a browser.** CORS is a
browser security mechanism — the Flutter HTTP client (`dio`) does not enforce it and does
not send an `Origin` header. CORS therefore has no effect on mobile-to-API requests.

CORS matters for:
- Any future browser-based client (admin portal, municipality WebView)
- Browser-based development tools (Postman web, browser DevTools fetch)
- The security design assumes both will exist at some point

### Configuration

```typescript
// shared/corsOptions.ts
import { CorsOptions } from 'cors'
import { env } from './env'

const allowedOrigins = env.ALLOWED_ORIGINS
  .split(',')
  .map(o => o.trim())
  .filter(Boolean)

export const corsOptions: CorsOptions = {
  origin: (origin, callback) => {
    // Allow requests with no Origin header:
    // — Flutter mobile app (dio sends no Origin)
    // — curl, Postman desktop, server-to-server calls
    // — health check endpoints called by Azure probe
    if (!origin) {
      callback(null, true)
      return
    }
    if (allowedOrigins.includes(origin)) {
      callback(null, true)
    } else {
      callback(new Error(`CORS: origin '${origin}' not in ALLOWED_ORIGINS`))
    }
  },

  // JWT is in Authorization header, not cookies.
  // credentials:true is only required when cookies carry session state.
  // Setting it false (the default) means the browser will not include cookies
  // or the Authorization header automatically — callers must set it explicitly.
  credentials: false,

  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],

  // Only these headers need to cross origins — keep the allowlist minimal.
  allowedHeaders: ['Authorization', 'Content-Type'],

  // Cache preflight response for 10 minutes — reduces OPTIONS requests
  maxAge: 600,
}
```

```typescript
// shared/app.ts
import cors from 'cors'
import { corsOptions } from './corsOptions'

app.use(cors(corsOptions))
```

### Environment variable per deployment

| Environment | `ALLOWED_ORIGINS` value |
|---|---|
| Local dev | `http://localhost:3000,http://localhost:8080` |
| Pilot | `https://easyrates.co.za` (or App Service default domain) |
| Production | `https://easyrates.co.za,https://admin.easyrates.co.za` |

`ALLOWED_ORIGINS=*` is never acceptable in any non-local environment.

---

## Checklist F — NODE_ENV=production in deployment | PASS

### Effect on Express and middleware

When `NODE_ENV=production`:
- Express disables stack traces in error responses
- Express enables response caching
- `bcrypt` uses compiled native bindings (faster)
- Many middleware libraries switch to production-safe modes
- `console.log` from development-only debug statements should be gated with
  `if (env.NODE_ENV !== 'production')` guards

### Azure App Service configuration

Set in Azure Portal → App Service → Configuration → Application Settings:

```
NODE_ENV = production
```

This is not in `.env` (which is for local development). Azure Application Settings
override `.env` at runtime.

### Startup check

The Zod schema (Checklist C) validates `NODE_ENV` against `['production', 'development', 'test']`.
A typo (`NODE_ENV=prod`) crashes the service at startup with a clear error rather than
running in an undefined mode.

---

## Checklist G — Error response sanitization | PASS

### Principle

No API error response, in any environment, contains:
- Stack traces
- File paths (from `__dirname`, `require.resolve`, etc.)
- SQL error messages (table names, column names, constraint names)
- Environment variable values
- Internal IP addresses or Azure resource names

Stack traces are logged server-side for observability. The client receives only a safe,
user-facing error envelope.

### Production error handler

```typescript
// shared/errorHandler.ts
import { Request, Response, NextFunction } from 'express'

// Use a discriminated union to handle Prisma and HTTP errors
interface AppError extends Error {
  statusCode?: number
  code?: string
}

export function errorHandler(
  err: AppError,
  req: Request,
  res: Response,
  _next: NextFunction,
): void {
  const isProd = process.env.NODE_ENV === 'production'

  // Log the full error (including stack) to server-side observability.
  // This never reaches the client.
  console.error({
    timestamp: new Date().toISOString(),
    method: req.method,
    path: req.path,
    statusCode: err.statusCode ?? 500,
    error: err.message,
    // Stack trace in development only — production logs should not
    // contain stack traces to avoid leaking file paths
    ...(isProd ? {} : { stack: err.stack }),
  })

  // Sanitize Prisma error codes before they reach the client.
  // Prisma errors (P2002 = unique constraint, P2025 = not found, etc.)
  // should map to HTTP 409 / 404, not expose DB internals.
  const statusCode = err.statusCode ?? 500

  res.status(statusCode).json({
    data: null,
    error: {
      code: err.code ?? 'internal_error',
      // Generic message in production — specific message only in development
      message: isProd
        ? 'An unexpected error occurred. Please try again.'
        : err.message,
      // No `stack` field, ever. No `details` that could expose internals.
    },
  })
}
```

### Registration (must be last middleware)

```typescript
// shared/app.ts — errorHandler must be registered AFTER all routes
app.use('/auth',      authRouter)
app.use('/otp',       otpRouter)
app.use('/property',  propertyRouter)
// ... other routers

// Must be last — Express identifies error handlers by arity (4 parameters)
app.use(errorHandler)
```

### Prisma error code mapping

```typescript
// shared/prismaErrorHandler.ts
import { Prisma } from '@prisma/client'

export function handlePrismaError(err: unknown): { statusCode: number; code: string; message: string } {
  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    switch (err.code) {
      case 'P2002': return { statusCode: 409, code: 'conflict', message: 'Resource already exists.' }
      case 'P2025': return { statusCode: 404, code: 'not_found', message: 'Resource not found.' }
      case 'P2003': return { statusCode: 409, code: 'conflict', message: 'Related resource does not exist.' }
      default:      return { statusCode: 500, code: 'internal_error', message: 'An unexpected error occurred.' }
    }
  }
  return { statusCode: 500, code: 'internal_error', message: 'An unexpected error occurred.' }
}
```

---

## Checklist H — `trust proxy` | PASS

Documented under Checklist B (HTTPS). Repeated here for visibility because it is the
most commonly omitted configuration item and breaks rate limiting silently.

```typescript
// shared/app.ts — line 1, before all middleware
app.set('trust proxy', 1)
```

**Without this line:** `authLimiter`, `otpSendLimiter`, `otpVerifyLimiter`, and
`refreshLimiter` all scope to `req.ip`. Azure App Service sends requests from an internal
IP. All IP-based limiters see the same IP for every request from every user and reach
their ceiling after 10 requests from any single legitimate user. **Rate limiting is
effectively broken.**

**With this line:** Express reads `req.ip` from the `X-Forwarded-For` header that Azure
inserts, which contains the client's real IP.

---

## Checklist I — JSON body size limit | PASS

Express's default body size limit for `express.json()` is **100 kb**. A malformed client
or attacker can send a 100 kb JSON body to any endpoint, which Express buffers in full
before Zod validation rejects it. At 500 concurrent sessions (pilot peak) and 100 kb
payloads, this is 50 MB of buffered request data — within the B1 App Service's 1.75 GB
RAM, but unnecessary.

```typescript
// shared/app.ts
// Explicit size limits — 64 kb covers all legitimate API payloads.
// The largest legitimate JSON body is an objection description (2,000 chars ≈ 2 kb).
app.use(express.json({ limit: '64kb' }))
app.use(express.urlencoded({ extended: false, limit: '64kb' }))
```

File uploads use `multer.memoryStorage()` with its own `limits.fileSize: 10_485_760`
(10 MiB) — the `express.json` limit does not apply to multipart routes.

---

## Checklist J — Content-Security-Policy | ACCEPT

**Decision: CSP disabled via `contentSecurityPolicy: false` in helmet.**

### Justification

EasyRates is a pure REST API server. It returns only:
- `application/json` responses (bill data, objection status, auth tokens, etc.)
- `application/pdf`, `image/jpeg`, `image/png` file downloads (evidence documents, proxied from Azure Blob)

CSP headers on `application/json` responses have **no effect in any browser.** Browsers
apply CSP only to HTML documents. A CSP header on a JSON response is parsed and discarded.

CSP headers on PDF/image file responses are similarly ignored — they apply to the document
that loaded the resource, not to the resource itself.

The Flutter native client **ignores HTTP headers entirely** except those it explicitly
reads (`Content-Type`, `Authorization`, `RateLimit-*`).

Enabling CSP would:
- Add a non-trivial header to every response (no security benefit)
- Require maintenance as the CSP policy is refined (ongoing cost)
- Produce false confidence that a browser-specific control is protecting a non-browser client

**Re-evaluate trigger:** If a browser-rendered endpoint is added (admin panel, municipality
portal, in-app WebView over an HTTPS URL), CSP becomes mandatory for that endpoint. Use
`res.setHeader('Content-Security-Policy', ...)` on that specific route rather than
globally, or create a separate Express app for browser-served content.

---

## Complete middleware wiring reference

```typescript
// shared/app.ts — complete wiring for every service
import express from 'express'
import helmet from 'helmet'
import cors from 'cors'
import './env'                       // 0. Crash fast on bad config — IMPORT FIRST
import { corsOptions } from './corsOptions'
import { errorHandler } from './errorHandler'

export function createApp(): express.Application {
  const app = express()

  // 1. Proxy trust — MUST be before rate limiters and req.ip usage
  app.set('trust proxy', 1)

  // 2. Security headers (helmet) — before routes
  app.use(helmet({
    contentSecurityPolicy: false,
    crossOriginEmbedderPolicy: false,
    hsts: { maxAge: 31_536_000, includeSubDomains: true, preload: true },
    frameguard: { action: 'deny' },
  }))

  // 3. CORS — before routes
  app.use(cors(corsOptions))

  // 4. Body parsing — explicit size limits
  app.use(express.json({ limit: '64kb' }))
  app.use(express.urlencoded({ extended: false, limit: '64kb' }))

  // 5. Health endpoint — unauthenticated, before JWT middleware
  app.get('/health', healthHandler)

  // 6. Service-specific routers (JWT middleware is applied per-router)
  // app.use('/auth', authRouter)
  // app.use('/otp', otpRouter)
  // etc.

  // 7. Error handler — MUST be last; Express identifies it by 4-arg signature
  app.use(errorHandler)

  return app
}
```

### Middleware order rationale

| Position | Middleware | Why it must be here |
|---|---|---|
| 1st | `trust proxy` | Must precede anything reading `req.ip` or `req.secure` |
| 2nd | `helmet` | Security headers on every response, including errors |
| 3rd | `cors` | Preflight OPTIONS must be handled before JWT checks reject them |
| 4th | `express.json` | Parse body before route handlers; size limit enforced here |
| 5th | `/health` | Unauthenticated; before JWT middleware that would block it |
| Last | `errorHandler` | Must see errors from all routes; Express requires 4-arg signature |

---

## Access log sanitization

HTTP access logs must **never** include:
- The `Authorization` header value (contains the JWT access token)
- Request bodies (may contain passwords in auth endpoints)
- Query parameters on search endpoints (may contain account numbers)

When adding access logging (e.g., `morgan`):

```typescript
import morgan from 'morgan'

// Custom token that redacts the Authorization header
morgan.token('auth-header', (req) => {
  const header = req.headers.authorization
  if (!header) return '-'
  // Log only the presence and scheme, not the token value
  return header.startsWith('Bearer ') ? 'Bearer [redacted]' : '[redacted]'
})

app.use(morgan(':method :url :status :res[content-length] - :response-time ms auth=:auth-header'))
```

Do not use `morgan('combined')` or `morgan('common')` without customization — both log
the full request URL and headers, which may include sensitive query parameters.

---

## Open items before production

| Item | Action | Trigger |
|---|---|---|
| Update plan/01-scaffold.md T2 | Replace `JWT_SECRET`/`JWT_REFRESH_SECRET` in scaffold Zod schema with `JWT_SIGNING_KEY_ID`/`KEY_VAULT_URL` per sessions.md Decision A | Before T2 is implemented |
| Add `git-secrets` or `secretlint` to CI | Pre-commit hook blocks credential commits | Before first developer joins |
| Azure App Service HTTPS-only mode | Enable in Azure Portal before pilot deployment | Before pilot launch |
| Access log sanitization | Add `morgan` with redacted Authorization token | Before pilot launch |
| Pre-commit hook | Block `.env` commits; block raw credentials | Before first developer joins |
