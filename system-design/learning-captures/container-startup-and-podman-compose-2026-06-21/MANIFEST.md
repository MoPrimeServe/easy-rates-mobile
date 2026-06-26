# Coverage Manifest — container-startup-and-podman-compose-2026-06-21

Every checkbox below traces to a unit in the captured markdowns. When `curriculum` builds
plans from this folder, every manifest item should appear in at least one plan task.
Checking off Todoist tasks → checking off manifest items → coverage proven.

## socratic: container startup ordering & the minimum viable set

- [ ] Round 1: three-part framing refinement (minimum-set-is-per-endpoint; Flutter-not-a-container; three signals) — in `socratic-container-startup-ordering/01-round-1.md`
- [ ] Round 2: first-call discovery (three shapes) + the three readiness signals table + port-vs-ready trap — in `02-round-2.md`
- [ ] Round 3: `depends_on` gates the wrong boundary + the hardest-to-diagnose triad — in `03-round-3.md`
- [ ] Compile artifact: definitions → background → components → pipeline → traced example → per-step implementation → per-step exercises + 3-sentence summary — in `compile-artifact.md`
- [ ] Compile §1 Definitions: container, healthcheck, three signals, depends_on, client, first API call, minimum set, startup-ordering bug — in `compile-artifact.md`
- [ ] Compile §4 Pipeline: 7-step life of the first call — in `compile-artifact.md`
- [ ] Compile §5 Concrete example: the t=0.0s→4.6s CI-box trace of `GET /me` — in `compile-artifact.md`
- [ ] Compile §6 from-first-principles: real db healthcheck, `/readyz` endpoint, client retry-with-backoff, 503-not-500 — in `compile-artifact.md`
- [ ] Compile §7 Exercise 1: prove signal #2 ≠ #3 with a sleep in the entrypoint — in `compile-artifact.md`
- [ ] Compile §7 Exercise 2: build the honest `/readyz` healthcheck and watch `health: starting` — in `compile-artifact.md`
- [ ] Compile §7 Exercise 3: force the killer bug to reproduce on demand (8s warmup, no retry, one-command demo) — in `compile-artifact.md`
- [ ] Compile §7 Exercise 4: close the bug three ways (compose / api / app) and compare — in `compile-artifact.md`

## unpack: Podman Compose

- [ ] Part 1 — what it is: Podman Compose / Podman / podman-compose / Compose Spec — in `unpack-podman-compose/01-what-it-is.md`
- [ ] Component a — Service (`services:` entry, ~one container) — in `02-components.md`
- [ ] Component b — Key differences from Docker Compose v2: daemonless, rootless, `version:` dead, pods — in `02-components.md`
- [ ] Component c — healthcheck (runs inside container; you define "healthy") — in `02-components.md`
- [ ] Component d — depends_on + condition: `service_started` vs `service_healthy` vs `service_completed_successfully` — in `02-components.md`
- [ ] Component e — Networks + DNS (service-name hostname; aardvark-dns) — in `02-components.md`
- [ ] Component f — Named volumes vs bind mounts (data vs live-reload code) — in `02-components.md`
- [ ] Component g — env_file + secrets distinction (special `.env` interpolation vs `env_file:` directive; `.gitignore` + `.env.example`; `secrets:` caveat) — in `02-components.md`
- [ ] Part 3 — pipeline: 7-step `podman-compose up` cold start + teardown — in `03-pipeline.md`
- [ ] Part 4 — mechanism: container health state machine `created→starting→healthy/unhealthy`, `start_period` grace, release-on-healthy — in `04-mechanism.md`
- [ ] Part 5 — concrete example: postgres+redis+auth slice traced through `up`; the `$$` interpolation bug — in `05-concrete-example.md`
- [ ] Exercise/Done-when: write a healthcheck block from memory — in `05-concrete-example.md`
- [ ] Exercise/Done-when: write a `depends_on` health condition from memory — in `05-concrete-example.md`
- [ ] Exercise/Done-when: write a named volume definition from memory — in `05-concrete-example.md`

## freeform: plan/08 build sequence & handoffs (operational)

- [ ] Build sequence INVENTORY → ASSIGN → HEALTHCHECKS → WRITE → VERIFY recorded — in `freeform-plan08-build-and-handoffs/overview.md`
- [ ] Decision: 9 app + postgres + redis + 2 dev-only; one container per service (ADR-001 §F) — same file
- [ ] Decision: resource budget Σ=0.90 vCPU / 1664 MB ≤ B1 pilot ceiling — same file
- [ ] Decision: queue-consumer health via side `/health` server — same file
- [ ] Contradiction 1: service-map.md single-process vs ADR-001 §F one-container — same file
- [ ] Contradiction 2: 7-vs-9 service drift (status + queue-consumer) — same file
- [ ] Open item: Prisma connection-pool breach (9×4=36>30; set to 3 pending plan/05) — same file
- [ ] Open item: VERIFY `podman-compose config` gate (needs podman host) — same file
- [ ] Open item: Postgres image tag ADR + service-map↔ADR-001 reconciliation; handoff to @architect — same file
