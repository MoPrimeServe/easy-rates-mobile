# 🐳 Container Topology

## Load Anchor (from envelope.md — do not derive independently)

> **Peak concurrent sessions (production): 5,000**
> **Peak concurrent sessions (pilot): 500**
>
> Basis: 20% of registered users (production: 25,000; pilot: 2,500) simultaneously in the
> peak 15-minute window of a WhatsApp-driven billing dispute spike. This is the worst-case
> load event — unscheduled, no advance warning, vertical ramp.
>
> Source: `easy_rates/system-design/docs/envelope.md` — envelope.md is the single source of
> truth. CPU and memory resource limits in this plan must be sized to serve 5,000 concurrent
> sessions (production) or 500 (pilot) without exceeding the P95 latency targets set in
> plan/05. This plan may not invent its own session estimate.

## Performance SLA (verbatim from plan/05-nfr.md — do not modify here)

_Source: `easy_rates/system-design/plans/05-nfr.md` § P95 Latency Targets._
_This table is the single source of truth for latency. Container CPU and memory limits in the ASSIGN task must be sized to meet these targets at the peak session anchors above. Neither this plan nor the ops team may change these figures — raise a change in plan/05 first._

| Endpoint | Pilot P95 | Production P95 | Tier that delivers it | What changes between tiers |
| --- | --- | --- | --- | --- |
| OTP send — `POST /otp/send` → 202 | **400 ms** | **200 ms** | Pilot: Basic + B1. Prod: S2 + P1v3 | Basic is HDD-backed; INSERT latency ~80–100 ms. S2 raises DTU throughput; INSERT ~15–25 ms. Async pattern removes Twilio from critical path in both tiers. |
| Property lookup — `GET /property/*` → 200 | **300 ms** | **100 ms** | Pilot: Basic + B1 + C0. Prod: S2 + P1v3 + C1 | C0 → C1 adds replication and higher bandwidth. At 98% cache hit, DB tier matters only on the 2% miss path. Cache hit path: ~5 ms both tiers. Miss path: ~100 ms pilot (HDD), ~20 ms production (S2). |
| Bill fetch — `GET /bill/*` → 200 | **500 ms** | **150 ms** | Pilot: Basic + B1 + C0. Prod: S2 + P1v3 + C1 | Bill JOIN (Bill + BillLineItem, 5 rows per bill) is heavier than property SELECT. HDD miss path: ~150–200 ms. S2 miss path: ~30–40 ms. 97% cache hit means P95 across all requests is in the cache-hit zone (~5 ms) in steady state; target set to cover spike warmup window. |
| Objection submit — `POST /objection` → 202 | **400 ms** | **300 ms** | Pilot: Basic + B1. Prod: S2 + P1v3 | Blob Storage metadata write (~30–50 ms same-region) + DB INSERT + BullMQ enqueue. S2 halves DB INSERT time. Production target tighter because objection deadline pressure makes latency UX-critical — a slow 202 makes users retry, generating duplicate submissions. |
| Notification list — `GET /notification` → 200 | **400 ms** | **150 ms** | Pilot: Basic + B1. Prod: S2 + P1v3 | Paginated SELECT on `(user_id, created_at DESC)` index. HDD: ~100–150 ms. S2: ~15–25 ms. No Redis cache; index from plan/06-data-model is the only latency lever. |

## Background

✅ GATE CLEARED (2026-06-21) — service/module names finalised (service-map.md
Ownership Matrix + ADR-001 §F: 9 services, one container each).
✅ GATE CLEARED (2026-06-21) — hosting target/tier/limits confirmed (nfr.md:
pilot = Basic + B1, 1 vCPU / 1.75 GB ceiling).

The compose file is the first place a developer meets the architecture. If it is wrong,
fragile, or requires manual steps to start, it creates friction that compounds every
time a new developer joins. The goal is: `podman-compose up` → all services healthy →
Flutter app makes a successful API call. No manual steps in between.

## Description

Design the Podman Compose topology for local development. Assign ports, internal
networks, volumes, health checks, and startup ordering. Produce the skeleton compose
file and the .env.example that accompanies it. Validate that the file parses without
errors and that the startup dependency chain is sound.

## Purpose

To answer: "what is the minimum set of containers that must be healthy before the
Flutter app can make a single successful API call — and how does the compose file
enforce that startup order?" Every `depends_on` relationship must be motivated.

## Goal

`easy_rates/system-design/podman-compose.skeleton.yml` + `easy_rates/system-design/.env.example`
— file parses without errors; every service from service-map.md is present; cold-start
dependency chain is explicit and correct.

## Tasks

- [x] ✅ THINK `/socratic "What is the minimum set of containers that must be healthy
  before the Flutter app can make a single successful API call — and what happens to
  the developer experience if one of those containers starts slowly or fails its
  health check? Which startup ordering bugs would be hardest to diagnose?"`
  ✓ verified (socratic dialogue + compile this session; min-viable set + dependency
  graph written to the compose header block)
  Done when: the minimum viable startup set is named; the dependency chain is
  described as a directed graph; the hardest-to-diagnose ordering bug is identified
  and mitigated in the compose file.
  Downstream: the minimum viable startup set and the dependency graph become a comment
  block at the top of podman-compose.skeleton.yml — write it there before any service
  block, so any developer reading the file sees the intended startup order without
  having to reverse-engineer the depends_on chain.

- [x] ✅ LEARN `/unpack "Podman Compose — key differences from Docker Compose v2,
  healthcheck syntax, depends_on with condition: service_healthy vs service_started,
  named networks for container-to-container DNS resolution, named volumes vs bind
  mounts for local dev, and how to pass secrets via env_file without committing them"`
  ✓ stated (no learning-capture folder; competence applied directly in WRITE —
  correct healthcheck blocks, depends_on health conditions, and named volumes shipped)
  Done when: you can write a correct Podman Compose healthcheck block, a
  depends_on clause with a health condition, and a named volume definition from
  memory.

- [x] ✅ INVENTORY List every container that belongs in the local dev environment.
  For each: role, image placeholder, required-for-startup (yes/no for the minimum
  viable set), and the health-check signal.
  Node.js app services (one per service module from service-map.md — 9 modules):
    auth, otp, property, account, bill, objection, notification, municipality, queue-consumer
    (roster reconciled 2026-06-21: `status` dissolved → `municipality` added; see open items)
  Infrastructure: PostgreSQL, Redis, queue broker (BullMQ uses Redis; add
    RabbitMQ only if chosen in plan/03)
  Dev-only (not needed for tests, useful for humans):
    pgAdmin, Bull Board (BullMQ job monitor)
  Done when: every service from service-map.md appears; every infrastructure
  dependency is listed; dev-only services are clearly marked.
  ✓ verified (9-service inventory in compose header; `status` + `queue-consumer`
  were missing from the original 7-name list — corrected here)

- [x] ✅ ASSIGN For each service in the inventory:
  External port : internal port (choose non-conflicting external ports)
  Internal network: one network name for the whole stack (e.g. `easyrates_net`)
  Volume mounts: code mount for Node.js services (for live reload in dev via
    `--watch` or `nodemon`), data volumes for PostgreSQL and Redis
  Resource limits: CPU and memory limits derived from nfr.md pilot tier
  Environment: `env_file: .env` for all secrets; explicit env vars for non-secret
    config (e.g. NODE_ENV)
  Done when: assignment table complete; no two services share the same external port.
  Downstream: the CPU and memory resource limits chosen here are copied verbatim into
  backend plans/01 (scaffold) as the deploy.resources limits in the backend's
  podman-compose.yml. No backend plan may set its own resource limits — they must
  reference the figures from nfr.md (plan/05) via this plan.
  ✓ verified (ports 3001–3010/5050/5432/6379, easyrates_net, code+data volumes,
  deploy.resources Σ=0.90 vCPU/1664 MB ≤ B1 — all present in compose)

- [x] ✅ HEALTHCHECKS Define a health-check block for each service type:
  Node.js services: `GET /health → 200` (document that this endpoint must be
    implemented in the Node.js scaffold before the compose file is useful)
  PostgreSQL: `pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB`
  Redis: `redis-cli ping`
  Done when: every service has a healthcheck block with interval, timeout, retries,
  and start_period values.
  ✓ verified (every service has interval+timeout+retries+start_period; queue-consumer
  resolved to a side /health server; /health-must-exist documented for the scaffold)

- [x] ✅ WRITE Write `easy_rates/system-design/podman-compose.skeleton.yml`:
  All services with `image: tbd/<name>:latest` placeholders, ports, networks,
  volumes, `env_file: .env`, `depends_on` with `condition: service_healthy` where
  applicable, and healthcheck blocks. No real credentials anywhere.
  Write `easy_rates/system-design/.env.example`:
  Every environment variable referenced in the compose file, with placeholder
  values and an inline comment explaining what the variable does and how to obtain
  it. Include at minimum:
  POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB, DATABASE_URL,
  REDIS_URL,
  TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_SERVICE_SID,
  NODE_ENV, PORT, ALLOWED_ORIGINS,
  JWT_SECRET, JWT_REFRESH_SECRET, JWT_ACCESS_TTL_SECONDS, JWT_REFRESH_TTL_DAYS,
  Done when: both files exist; every service from the inventory is in the compose
  file; every env var referenced in the compose file is in .env.example with a
  comment.
  ✓ verified (podman-compose.skeleton.yml 12K + .env.example 3.3K exist; 13 services
  present; all 15 required env vars documented with comments; no inline secrets)

- [x] ✅ VERIFY Run `podman-compose -f podman-compose.skeleton.yml config`.
  Must exit 0. Fix any parse errors before this plan closes.
  Then trace the startup dependency chain manually: start from the Node.js app
  containers and follow every `depends_on` back to its dependency. Confirm that
  PostgreSQL and Redis (the deepest dependencies) have no `depends_on` of their
  own that could deadlock startup.
  Done when: `podman-compose config` exits 0; dependency chain has no cycles;
  startup order is documented as a numbered sequence in the plan notes.
  ✓ verified (2026-06-27 — `podman-compose -f podman-compose.skeleton.yml config`
  EXIT=0 with podman 4.1.1 + podman-compose 1.6.0; rendered config = 11 services
  (9 app + postgres + redis, dev-only excluded sans --profile dev), anchors
  *node-healthcheck/*app-deps resolved per service, roots postgres/redis have no
  depends_on → no deadlock; cycle-free; numbered startup sequence in VERIFY Notes.
  The one remaining gate from the 2026-06-21 PARTIAL is now closed — see Execution Note.)

## Recommended skill

▶ `/socratic` ✅ — THINK task; the minimum-viable-startup framing drives every
   `depends_on` relationship and surfaces ordering bugs before the compose file is
   written.
   alt: `/unpack` ✅ — Podman Compose healthcheck and depends_on syntax if the
   Podman-specific behaviour is unfamiliar.

## Engagement Instructions

```bash
# 1. Compose file parses without errors
podman-compose -f easy_rates/system-design/podman-compose.skeleton.yml config \
  > /dev/null 2>&1 && echo "PASS: config valid" || echo "FAIL: parse error"
# Expected: PASS

# Fallback if podman-compose is not installed locally:
python3 -c "import yaml,sys; yaml.safe_load(open('easy_rates/system-design/podman-compose.skeleton.yml'))" \
  && echo "PASS: valid YAML" || echo "FAIL: YAML error"

# 2. All 9 app services from service-map.md + 2 infra present
for svc in "auth" "otp" "property" "account" "bill" \
           "objection" "notification" "municipality" "queue-consumer" \
           "postgres|postgresql" "redis"; do
  printf "%-25s %s\n" "$svc:" \
    "$(grep -icE "$svc" easy_rates/system-design/podman-compose.skeleton.yml)"
done
# Expected: each ≥ 1

# 3. No hard-coded credentials (passwords, tokens, secrets)
grep -iE "password\s*:\s*['\"]?[a-zA-Z0-9]{6,}|secret\s*:\s*['\"]?[a-zA-Z0-9]{6,}" \
  easy_rates/system-design/podman-compose.skeleton.yml
# Expected: 0 results (all secrets via env_file or \${VAR} references)

# 4. All required env vars present in .env.example
for var in "POSTGRES_USER" "POSTGRES_PASSWORD" "POSTGRES_DB" "DATABASE_URL" \
           "REDIS_URL" "TWILIO_ACCOUNT_SID" "TWILIO_AUTH_TOKEN" \
           "JWT_SECRET" "JWT_REFRESH_SECRET" \
           "JWT_ACCESS_TTL_SECONDS" "JWT_REFRESH_TTL_DAYS" \
           "NODE_ENV" "ALLOWED_ORIGINS"; do
  printf "%-30s %s\n" "$var:" \
    "$(grep -c "$var" easy_rates/system-design/.env.example)"
done
# Expected: each ≥ 1 (with inline comment)

# 5. Startup dependency chain documented (comment block or depends_on entries)
grep -iE "depends_on|startup.*order|minimum.*viable|dependency.*chain" \
  easy_rates/system-design/podman-compose.skeleton.yml | wc -l
# Expected: ≥ 3 (postgres + redis as roots; app services depend on them)

# 6. Dev-only services clearly marked
grep -iE "pgAdmin\|pgadmin\|bull.*board\|dev.only\|# dev" \
  easy_rates/system-design/podman-compose.skeleton.yml | wc -l
# Expected: ≥ 1 (dev-only services present and labelled)

# 7. Redis image tag matches queue-topology.md (cross-plan check from plan/03)
QT_TAG=$(grep -oiE "redis:[a-z0-9.-]+" \
  easy_rates/system-design/docs/queue-topology.md 2>/dev/null | head -1)
CT_TAG=$(grep -oiE "redis:[a-z0-9.-]+" \
  easy_rates/system-design/podman-compose.skeleton.yml | head -1)
echo "queue-topology: $QT_TAG | compose: $CT_TAG"
# Expected: both show the same image tag (e.g. redis:7-alpine)
```

Gate: checks 1–6 must pass before this plan closes.
Check 7 is a cross-plan consistency gate — run it after plan/03 is complete.
A tag mismatch means the queue worker was designed against one Redis version
and the container runs another; silent incompatibilities are the result.

## VERIFY Notes (2026-06-21)

**Artifacts:** `podman-compose.skeleton.yml` (13 containers) + `.env.example`.

**Parser result.** This environment has no container runtime — `podman` is
absent, so `podman-compose config` cannot exit 0 here (podman-compose 1.6.0
hard-requires the `podman` binary even for `config`). Used the plan-sanctioned
fallback (`yaml.safe_load`) PLUS a semantic validator that resolves the YAML
anchors/merges and checks the dependency graph directly. **Re-run
`podman-compose -f podman-compose.skeleton.yml config` on a machine with podman
before final close** — this is the one gate not satisfiable in this environment.

**Semantic validation — all PASS:**

- 13 services load; anchors (`*node-healthcheck`, `*app-deps`, `*app-env`) resolve.
- Every `depends_on` target exists and uses `condition: service_healthy` (20 edges).
- Roots `postgres` and `redis` have **no `depends_on`** → no deadlock.
- **No cycles** (3-colour DFS).
- External ports unique: 3001–3010, 5050, 5432, 6379.
- Every service has both `image:` and `healthcheck:`.

**Numbered startup sequence** (topological; `depends_on: service_healthy` enforces it):

1. `postgres` → healthy (`pg_isready`)
2. `redis` → healthy (`redis-cli ping`)
3. 8 HTTP app services in parallel — `auth, otp, property, account, bill,
   objection, notification, municipality` → healthy (`GET /health`, real DB query)
4. `queue-consumer` → healthy (side `/health` server, Redis-ready)
5. `pgadmin`, `bull-board` — dev profile only (`--profile dev`); nothing depends on them

Minimum viable set for the app's first call (`GET /auth/session`):
`postgres` + `redis` + `auth` (steps 1–3a).

**Open items carried out of this plan (other owners):**

- Prisma pool: `.env.example` sets `connection_limit=3` (9×3=27<30); nfr.md still
  says 4 on 7-service math (36>30 breach). → ratify in plan/05.
- Pin the Postgres image tag in an ADR (currently `postgres:16-alpine` placeholder).
- Reconcile service-map.md single-process diagram vs ADR-001 §F; fix the
  "7 services" wording in this plan's INVENTORY list, VERIFY check 2, and nfr.md.
- **Service roster drift (sync 2026-06-21, from plan/09 api-contracts):** status-service
  was dissolved — its GET-status route folded into objection-service and a new
  municipality-service created for the inbound webhook.
  - ✅ DONE (2026-06-21): roster source of truth reconciled — `service-map.md` and
    `ADR-001 §F` + traceability matrix now show `municipality-service` and route the former
    status screens/calls into objection-service / account-service (ADR amendment dated).
  - ✅ DONE (2026-06-21): `podman-compose.skeleton.yml` updated — `status` container
    replaced by `municipality` (port 3008, same B1 footprint; Σ unchanged at 0.90 vCPU/1664 MB);
    header contradictions + cold-start sequence updated; `.env.example` gains
    `MUNICIPAL_WEBHOOK_SECRET`. INVENTORY list + VERIFY check 2 + startup sequence above
    re-pointed to `municipality`. Roster drift fully closed across plan/08, service-map.md,
    and ADR-001.

## Execution Note — 2026-06-27

**VERIFY gate closed — the literal `podman-compose config` now exits 0.**

The 2026-06-21 PARTIAL left exactly one item open: the 2026-06-21 environment had no
`podman` binary, so `podman-compose config` could not be run literally (podman-compose
1.6.0 hard-requires `podman` even for `config`). That binary became installable this
session (`conda install -c conda-forge podman` → `/home/molef/miniconda3/bin/podman`).

Command run (from `easy_rates/system-design/`):

```text
podman-compose -f podman-compose.skeleton.yml config   →  EXIT=0   (clean stderr)
```

Versions: podman 4.1.1, podman-compose 1.6.0.

Evidence the rendered output is substantive (not a degenerate empty parse):

- 11 services rendered: `auth, otp, property, account, bill, objection, notification,
  municipality, queue-consumer` + `postgres` + `redis`. The 2 dev-only services
  (`pgadmin`, `bull-board`) are correctly absent because `--profile dev` was not passed.
- Compose extension-field anchors (`*node-healthcheck`, `*app-deps`, `*app-env`) resolve:
  every app service carries a rendered `healthcheck` block and `depends_on: [postgres, redis]`.
- Roots `postgres` and `redis` render with `depends_on = None` → no deadlock; chain is
  cycle-free. This matches the 2026-06-21 semantic-validator result (20 edges, all
  `condition: service_healthy`), now confirmed by the real tool.

The numbered cold-start sequence is unchanged and remains documented in the VERIFY Notes
(2026-06-21) section above. **All Done-when conditions satisfied; this plan's last open
task is closed and the gate is ✅ resolved.**
