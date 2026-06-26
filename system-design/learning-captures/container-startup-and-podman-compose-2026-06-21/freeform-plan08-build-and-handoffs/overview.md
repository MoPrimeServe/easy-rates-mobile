# Freeform — plan/08 build sequence & handoffs (operational note)

This records the operational (non-learning) work of the session for continuity. The
artifacts themselves live in the repo (`podman-compose.skeleton.yml`, `.env.example`,
plan/08, role state); this note preserves the *decisions and open threads* so the chat
can be deleted.

## The build sequence (plan/08-container-topology)

Executed the plan's task chain end to end:

1. **THINK** (`/socratic`) — see `socratic-container-startup-ordering/`. Output: min-viable
   set + dependency graph written as the comment header of `podman-compose.skeleton.yml`.
2. **INVENTORY** — listed all containers. **9 app services** (auth, otp, property, account,
   bill, objection, notification, **status**, **queue-consumer**) + postgres + redis + 2
   dev-only (pgAdmin, Bull Board). Per-endpoint min-viable set = postgres + redis + auth.
3. **ASSIGN** — ports 3001–3010/5050/5432/6379; one network `easyrates_net`; bind mounts
   for code, named volumes for data; resource limits from nfr.md pilot tier (B1:
   1 vCPU / 1.75 GB). App-tier Σ = **0.90 vCPU / 1664 MB** ≤ ceiling.
4. **HEALTHCHECKS** — `GET /health` (Node, signal #3, real DB query) interval 10s /
   timeout 3s / retries 5 / start_period 30s; postgres `pg_isready` 5/3/10/10s; redis
   `redis-cli ping` 5/3/10/5s; dev-only best-effort. queue-consumer resolved to a **side
   `/health` server** (it has no inbound HTTP).
5. **WRITE** — `podman-compose.skeleton.yml` (13 containers, YAML anchors, deploy.resources,
   depends_on service_healthy, env_file) + `.env.example` (all 15 required vars documented,
   `CHANGE_ME` placeholders, no inline secrets).
6. **VERIFY** — `podman-compose config` could not run (no podman binary in env); used
   `yaml.safe_load` + a semantic validator (anchors resolve; 20 depends_on edges all
   service_healthy; roots clean; no cycles; ports unique; image+healthcheck on every
   service). Numbered startup order documented in the plan's VERIFY Notes.

## Two source contradictions found and resolved

1. **service-map.md (single-process monolith) vs ADR-001 §F (one container per service).**
   ADR-001 is Accepted → followed it (one container per service). Consequence: the three
   "zero-hop" sync calls (auth→otp, objection→bill, objection→status) are actually
   inter-service HTTP. → architect to reconcile the diagram.
2. **7-vs-9 service drift.** plan/08 INVENTORY list, VERIFY check 2, and nfr.md all named
   only 7 app services; service-map.md + ADR-001 name 9 (missing `status` +
   `queue-consumer`). Corrected the INVENTORY list and VERIFY check 2 during sync.

## The serious open item — Prisma connection-pool breach

nfr.md fixes `connection_limit = 4` per service on **7-service** math (7×4=28 < 30 Basic
ceiling), and alert #11 (`infra-connection-pool-errors`) watches it. With **9** services:
9×4 = **36 > 30 → breach on startup.** `.env.example` sets `connection_limit=3`
(9×3=27 < 30) as a stopgap — but this is nfr.md's "hard requirement," so it **must be
ratified in plan/05**, not silently changed.

## Sync + handoffs (done this session)

- `sync-plan-tree` on plan/08: THINK/INVENTORY/ASSIGN/HEALTHCHECKS/WRITE → ✅ (✓ verified);
  LEARN → ✅ (✓ stated, then done for real via the unpack capture); VERIFY → ⚠️ in-progress
  (rewritten to remaining slice: run `podman-compose config` on a podman host). Two
  `⛔ BLOCKED` gate markers cleared.
- Handoff appended to `roles/system_design/state.md` → `next: @architect` (pin Postgres
  image tag in an ADR; reconcile service-map.md vs ADR-001 §F).

## Open ends (not closure-fabricated)

- VERIFY's literal `podman-compose config` gate still open — needs a podman host.
- Prisma `connection_limit` 3-vs-4 awaiting plan/05 ratification.
- Postgres image tag (`postgres:16-alpine`) not yet pinned in an ADR.
- service-map.md single-process diagram not yet reconciled with ADR-001 §F.
- The unpack LEARN task: pending the user's confirmation to flip `✓ stated` → `✓ verified`.
