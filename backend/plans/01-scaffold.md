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

- [ ] ⚠️ T0a  Install prerequisites on the local machine:
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

- [ ] ⚠️ T0b  Confirm workspace and copy env file:
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

- [ ] ⚠️ T1  Create the monorepo layout on disk:
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

- [ ] ⚠️ T2  Write `easy_rates/backend/shared/env.ts` — Zod schema over `process.env`
  validating all required vars:
  `DATABASE_URL, REDIS_URL, JWT_SECRET, JWT_REFRESH_SECRET, TWILIO_ACCOUNT_SID,
  TWILIO_AUTH_TOKEN, TWILIO_MOCK, QUEUE_URL, AUTH_PORT, OTP_PORT, PROPERTY_PORT,
  NODE_ENV`.
  Import and call at each service's entry point — throw with a readable message
  (not a stack trace) if any var is missing.
  Done when: removing `DATABASE_URL` from `.env` causes startup to print
  `[config] Missing required env var: DATABASE_URL` and exit 1 — not a runtime
  crash.

- [ ] ⚠️ T3  Promote `easy_rates/system-design/podman-compose.skeleton.yml` to
  `easy_rates/backend/podman-compose.yml`. Replace image placeholders with
  `build:` paths pointing to each service directory. Add:
  - `postgres` service with named volume, health check (`pg_isready`), and
    `DATABASE_URL` env from `.env`
  - `redis` service with named volume and health check (`redis-cli ping`)
  - queue broker service (image from ADR-001) with named volume and health check
  Done when: `podman-compose config` validates without errors.

- [ ] ⚠️ T4  Write `.env.example` — every variable from T2 with a one-line comment
  describing its purpose and an example value (no real credentials).
  Copy to `.env` for local dev; `.env` is gitignored.
  Done when: `.env.example` contains every variable; the comment explains what
  it does.

- [ ] ⚠️ T5  Add `GET /health` to each service. Response shape:
  ```json
  { "status": "ok", "service": "<name>", "db": "connected", "queue": "connected" }
  ```
  DB check: `SELECT 1` via Prisma (catches connection failure).
  Queue check: ping the broker (method depends on ADR queue choice).
  On any failure: return 503 with the failing component named.
  Done when: all three service `/health` routes exist and compile.

- [ ] ⚠️ T6  `podman-compose up --build` → wait for health checks → `curl` each
  `/health` endpoint → assert HTTP 200 and `db: "connected"` in response body.
  Done when: all three `/health` calls return 200 with connected status; no
  container exits unexpectedly.

- [ ] ⚠️ T7  `git commit -m "Backend scaffold — services start, Zod config, health checks"`
  Done when: commit is clean; no `.env` file committed; no hardcoded credentials.

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
