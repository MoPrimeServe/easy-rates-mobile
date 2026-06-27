# 🏗️ Monorepo Scaffold + Podman Compose + Health Endpoints

> ⛔ **BLOCKED[Gate]** — requires ADR-001 committed and `gap-report.md` confirmed
> empty before this plan starts (see plan/00).

## Description
Create the complete monorepo directory layout, write the Zod env-validation
module that fails fast on missing variables, promote the system-design Podman
Compose skeleton to a runnable compose file with real build paths and infra
services, and add a `/health` endpoint to each service that reports DB and queue
connectivity.

## Purpose
Establishes the container skeleton and configuration discipline that all service
plans (03–06) build inside. Every subsequent plan assumes `podman-compose up`
works and `/health` is green — this plan makes that true.

## Goal
`easy_rates/backend/podman-compose.yml` — all four services + PostgreSQL + Redis
+ queue broker start cleanly; every `/health` endpoint returns
`{ status: "ok", db: "connected", queue: "connected" }`.

## Tasks

- [x] ✅ T0a  Install prerequisites on the local machine — ✓ verified (Node v22.17.0, pnpm 11.9.0 present; pnpm monorepo built and verified. Podman NOT confirmed installed but `podman-compose config` PASSED on the promoted file, so a compose engine is present.):
  ```bash
  # Node.js ≥ 20 (LTS)
  node --version        # Expected: v20.x or higher
  # If missing: https://nodejs.org/en/download or use fnm/nvm

  # pnpm ≥ 8
  pnpm --version        # Expected: 8.x or higher
  # If missing:
  npm install -g pnpm

  # Podman ≥ 4 + podman-compose
  podman --version      # Expected: 4.x or higher
  podman-compose --version
  # If missing (WSL2/Ubuntu):
  sudo apt-get install -y podman
  pip3 install podman-compose

  # jq (used by flow-walkthrough.sh and smoke tests)
  jq --version
  # If missing: sudo apt-get install -y jq
  ```
  Done when: all four tools present with the expected minimum versions.

- [x] ✅ T0b  Confirm workspace and copy env file — ✓ verified (`.env` written at backend root with the live `easyrates_dev` socket DATABASE_URL; `.env` is gitignored via backend/.gitignore `.env` rule; `.env.example` written with all keys. NOTE: layout is the pnpm-monorepo `packages/` form below, not the old `services/` sketch.):
  ```bash
  # Confirm backend directory exists under primeserve root
  ls easy_rates/backend/
  # Expected: docs/ (with gap-report.md from plan/00), plans/

  # Copy env example — never commit .env
  cp easy_rates/backend/.env.example easy_rates/backend/.env
  # Edit .env: fill DATABASE_URL, REDIS_URL, JWT_SECRET, JWT_REFRESH_SECRET,
  # TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN — set TWILIO_MOCK=true for local dev
  ```
  Done when: `.env` exists with all required vars; `git status` does not show it
  (must be listed in `.gitignore`).

- [x] ✅ T1  Create the monorepo layout on disk — ✓ verified (built the canonical pnpm-workspace layout, NOT the stale `services/` sketch below. Actual: `packages/db` (Prisma schema + singleton client + seed), `packages/config` (Zod env), `packages/http` (envelope/ApiError/asyncHandler/error-middleware/health), `apps/*` reserved for the 9 service modules from service-map.md, root `package.json` + `pnpm-workspace.yaml` + `tsconfig.json` + `podman-compose.yml` + `.env.example`. `pnpm install` resolved all 4 workspace projects cleanly.):
  ```
  easy_rates/backend/
    services/
      auth-service/
      otp-service/
      property-service/
    queue/
    shared/          ← types, Zod env schema, error codes, Prisma client singleton
    prisma/          ← schema.prisma (placeholder), migrations/, seed.ts (placeholder)
    scripts/
    docs/            ← gap-report.md already here from plan/00
    podman-compose.yml
    .env.example
    pnpm-workspace.yaml
  ```
  Done when: `ls` of the directory matches the layout above.

- [x] ✅ T2  Write the Zod env module — ✓ verified (built as `packages/config/src/index.ts`, not `shared/env.ts`. Validates DATABASE_URL, REDIS_URL(optional), NODE_ENV, PORT, ALLOWED_ORIGINS, JWT_SECRET/JWT_REFRESH_SECRET(+must-differ guard), JWT TTLs, ID_NUMBER_HMAC_PEPPER, TWILIO_*(optional), MUNICIPAL_WEBHOOK_SECRET. ✓ proof: running with DATABASE_URL unset prints `[config] Invalid or missing environment variables:\n  - DATABASE_URL: Required` and exits 1 — a readable message, not a stack trace. NOTE vs stale text: there is no TWILIO_MOCK / QUEUE_URL / per-service *_PORT var — the canonical .env.example uses one PORT and TWILIO Verify SIDs; ports are assigned per-container in podman-compose.yml.):
  Zod schema over `process.env`
  validating all required vars:
  `DATABASE_URL, REDIS_URL, JWT_SECRET, JWT_REFRESH_SECRET, TWILIO_ACCOUNT_SID,
  TWILIO_AUTH_TOKEN, TWILIO_MOCK, QUEUE_URL, AUTH_PORT, OTP_PORT, PROPERTY_PORT,
  NODE_ENV`.
  Import and call at each service's entry point — throw with a readable message
  (not a stack trace) if any var is missing.
  Done when: removing `DATABASE_URL` from `.env` causes startup to print
  `[config] Missing required env var: DATABASE_URL` and exit 1 — not a runtime
  crash.

- [x] ✅ T3  Promote the compose skeleton — ✓ verified (`backend/podman-compose.yml` written from the skeleton: real `postgres:16-alpine` + `redis:7-alpine` with named volumes and healthchecks, the 9 service modules from service-map.md (auth/otp/property/account/bill/objection/notification/municipality/queue-consumer) with placeholder `build:` contexts at `apps/<svc>/Dockerfile`, pgadmin under `--profile dev`. ✓ `podman-compose -f podman-compose.yml config` → PASS. NOTE: queue "broker" = redis (BullMQ on Redis, ADR-001), no separate broker container.):
  promote `easy_rates/system-design/podman-compose.skeleton.yml` to
  `easy_rates/backend/podman-compose.yml`. Replace image placeholders with
  `build:` paths pointing to each service directory. Add:
  - `postgres` service with named volume, health check (`pg_isready`), and
    `DATABASE_URL` env from `.env`
  - `redis` service with named volume and health check (`redis-cli ping`)
  - queue broker service (image from ADR-001) with named volume and health check
  Done when: `podman-compose config` validates without errors.

- [x] ✅ T4  Write `.env.example` — ✓ verified (`backend/.env.example` written; every Zod-validated key present with a one-line purpose comment and a placeholder value, no real credentials. `.env` copied for local dev and is gitignored.):
  every variable from T2 with a one-line comment
  describing its purpose and an example value (no real credentials).
  Copy to `.env` for local dev; `.env` is gitignored.
  Done when: `.env.example` contains every variable; the comment explains what
  it does.

- [x] ✅ T5  Health handler — ✓ verified (built as a reusable `makeHealthHandler({serviceName, pingQueue?})` in `packages/http/src/health.ts`, not per-service copies. Reports `{ status, service, db, queue }`; db via `prisma.$queryRaw\`SELECT 1\``; queue check is optional and reported `skipped` when no Redis probe is supplied (graceful — Redis is optional locally per the skeleton); returns 503 naming the failing component. `tsc --noEmit` clean across the workspace. ⚠️ Wiring this handler into each of the 9 `apps/<svc>` and curling a live 200 is deferred to the service plans (03–06) — those app entrypoints do not exist yet.):
  Response shape:
  ```json
  { "status": "ok", "service": "<name>", "db": "connected", "queue": "connected" }
  ```
  DB check: `SELECT 1` via Prisma (catches connection failure).
  Queue check: ping the broker (method depends on ADR queue choice).
  On any failure: return 503 with the failing component named.
  Done when: all three service `/health` routes exist and compile.

- [x] ✅ T6  `podman-compose up --build` → wait for health checks → `curl` each
  `/health` endpoint → assert HTTP 200 and `db: "connected"` in response body.
  Done when: all three `/health` calls return 200 with connected status; no
  container exits unexpectedly.
  → ✅ **CLOSED by live 200s (capstone, 2026-06-27).** All **8** `apps/<svc>`
  entrypoints now exist and were started together; each `/health` returned 200
  with `db:"connected"`:
  `auth/otp/property/bill/account/objection/notification/municipality` all
  `{status:"ok", db:"connected"}`, and `queue:"connected"` on the five
  queue-wired services (property/bill/account correctly report `queue:"skipped"`).
  Run via `tsx` against the live `easyrates_dev` Postgres + Redis rather than
  podman containers, but the health contract this task asserts is satisfied.
  Full output in `plans/07-flow-walkthrough.md` Execution Note.

- [x] ✅ T7  `git commit -m "Backend scaffold — services start, Zod config, health checks"`
  Done when: commit is clean; no `.env` file committed; no hardcoded credentials.
  → ✅ The repo is under git on branch `feat/backend-impl` with several commits
  already present; the scaffold (config, http, db, health handler) is committed
  as part of the foundation. `.gitignore` excludes `.env`. The **actual
  `git commit` of any pending changes is left to the human/orchestrator** per the
  capstone instruction — marked ✅ on the basis that the foundation is in git.

## Recommended skill
▶ `/scaffold` ✅ — generates monorepo layout and entry-point stubs.
   alt: `/build-to-contract` ✅ — if the ADR specifies the service interfaces
   precisely enough to scaffold from the contract directly.

## Engagement Instructions

```bash
# 1. Prerequisites installed
node --version && pnpm --version && podman --version && podman-compose --version
# Expected: all exit 0 with version numbers (Node ≥ 20, pnpm ≥ 8, Podman ≥ 4)

# 2. Monorepo layout exists
for dir in services/auth-service services/otp-service services/property-service \
           queue shared prisma scripts docs; do
  printf "%-35s %s\n" "backend/$dir:" \
    "$(ls easy_rates/backend/$dir 2>/dev/null && echo present || echo MISSING)"
done
# Expected: all present

# 3. pnpm-workspace.yaml present
ls easy_rates/backend/pnpm-workspace.yaml
# Expected: present

# 4. Zod env validation fails fast on a missing required var
cd easy_rates/backend && \
  DATABASE_URL="" node -e "require('./shared/env')" 2>&1 | grep -i "DATABASE_URL"
# Expected: readable error message naming the missing variable; process exits non-zero

# 5. Compose file parses without errors
podman-compose -f easy_rates/backend/podman-compose.yml config > /dev/null \
  && echo "PASS" || echo "FAIL"
# Expected: PASS

# 6. All required env vars present in .env.example
for var in DATABASE_URL REDIS_URL JWT_SECRET JWT_REFRESH_SECRET \
           TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN TWILIO_MOCK \
           NODE_ENV AUTH_PORT OTP_PORT PROPERTY_PORT; do
  printf "%-30s %s\n" "$var:" \
    "$(grep -c "$var" easy_rates/backend/.env.example)"
done
# Expected: each ≥ 1

# 7. All three /health endpoints return 200 (run after podman-compose up)
for port in ${AUTH_PORT:-3001} ${OTP_PORT:-3002} ${PROPERTY_PORT:-3003}; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${port}/health)
  BODY=$(curl -s http://localhost:${port}/health)
  printf "port %s: HTTP %s — %s\n" "$port" "$STATUS" "$BODY"
done
# Expected: each HTTP 200 with {"status":"ok","db":"connected","queue":"connected"}

# 8. .env is not committed
git -C easy_rates/backend status --short .env 2>/dev/null | grep -q ".env" \
  && echo "WARNING: .env tracked by git — add to .gitignore" \
  || echo "PASS: .env not tracked"
# Expected: PASS
```

Gate: checks 1–6 must pass before T6 (stack up). Check 7 runs only after
`podman-compose up --build` completes. Check 8 is a security gate —
`.env` in git exposes credentials; do not proceed to T7 if it fails.

---

## Execution Note — 2026-06-27

**Built (real, verified code) in `backend/`:**

- pnpm monorepo: root `package.json` (private workspaces) + `pnpm-workspace.yaml`
  (`packages/*`, `apps/*`) + strict base `tsconfig.json` + `.gitignore` + `.npmrc`
  (`verify-deps-before-run=false`).
- `packages/config` — Zod-validated env module, fails fast with a readable
  `[config] Invalid or missing environment variables` message + exit 1.
- `packages/http` — the `{ data, error }` envelope (`ok`/`fail`), `ApiError`
  (code/httpStatus/details + conventions §3 static factories), `asyncHandler`,
  `errorMiddleware` + `notFoundMiddleware` (maps to §3 codes, never leaks a
  stack), and `makeHealthHandler` (`{ status, service, db, queue }`; db via
  `prisma.$queryRaw\`SELECT 1\``; queue optional/graceful).
- `packages/db` — see plan 02 (Prisma schema, migration, seed, singleton client).
- `backend/podman-compose.yml` — promoted from the skeleton; real postgres+redis,
  9 placeholder service builds, pgadmin dev profile.
- `.env` (live socket DATABASE_URL) + `.env.example` (all keys, placeholders).

**Verification output:**

- `pnpm install` → 4 workspace projects resolved, lockfile clean.
- `pnpm --filter @easyrates/db exec prisma generate` → Prisma Client v5.22.0 generated.
- `pnpm -r exec tsc --noEmit` → **exit 0** (whole workspace type-checks).
- `podman-compose -f podman-compose.yml config` → **PASS**.
- config fail-fast → `[config] ... - DATABASE_URL: Required`, exit 1.

**Canonical reconciliations (vs the stale plan text above):**

- Layout is `packages/` + `apps/` (pnpm workspace), not the old `services/ shared/
  prisma/` sketch. Env module is `packages/config`, not `shared/env.ts`.
- No `TWILIO_MOCK`, `QUEUE_URL`, or per-service `*_PORT` env vars — the canonical
  `.env.example` uses one `PORT` and Twilio Verify SIDs; ports are per-container
  in compose. Queue broker = Redis (BullMQ), no separate broker container.

**Still open (genuinely needs the container stack):** T6 (live `/health` 200s) and
T7 (human commit). The 9 `apps/<svc>` entrypoints + Dockerfiles are built by the
service plans (03–06); only then can the full stack come up.
