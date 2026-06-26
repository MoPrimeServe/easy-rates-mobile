# Unpack — Podman Compose

**What was unpacked:** Podman Compose — key differences from Docker Compose v2,
healthcheck syntax, `depends_on` with `condition: service_healthy` vs `service_started`,
named networks for container-to-container DNS resolution, named volumes vs bind mounts
for local dev, and how to pass secrets via `env_file` without committing them.

**Mode:** Mode 1 (concept explanation), five-part structure. This is the LEARN task of
plan/08, done for real after being provisionally marked `✓ stated`.

**Five-part structure:**
1. What it is — `01-what-it-is.md`
2. The components (dependency order) — `02-components.md`
3. The pipeline (`podman-compose up`) — `03-pipeline.md`
4. The mechanism that matters (no math; the container health state machine) — `04-mechanism.md`
5. A concrete example (the EasyRates postgres+redis+auth slice) — `05-concrete-example.md`

Plus a closing "three things from memory" recap (healthcheck block, depends_on health
condition, named volume) — captured at the end of `05-concrete-example.md`.

**Done-when (the task's competence gate):** be able to write, from memory, a correct
healthcheck block, a `depends_on` health condition, and a named volume definition.

## Revisions
None.
