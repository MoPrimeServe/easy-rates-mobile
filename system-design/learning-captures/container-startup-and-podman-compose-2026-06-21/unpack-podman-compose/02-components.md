# 2. The components

Each piece, in the order each depends on the one before.

**a. Service.** One entry under `services:` in the YAML. One service usually = one
container. `auth`, `postgres`, `redis` are services. Each names its image, and optionally
ports, volumes, network, and the parts below.

**b. Key differences from Docker Compose v2.** Same file format, different engine. Four
that matter:
- **Daemonless.** Docker runs a background daemon (`dockerd`) that owns every container.
  Podman has no daemon — each container is a normal child process of your shell. Nothing
  to "start" first.
- **Rootless by default.** Podman runs as your user, not root. Safer, but host ports below
  1024 need extra privilege — a real reason pgAdmin maps to host `5050`, not `80`.
- **`version:` is dead.** Old Docker files began with `version: "3.8"`. The Compose Spec
  dropped it; both Podman and Docker v2 ignore it. The EasyRates file correctly omits it.
- **Pods.** Podman can group containers into a "pod" (shared network namespace, a
  Kubernetes idea). podman-compose historically put a project's services in one pod;
  current versions lean on networks instead, like Docker. No manual management needed.

**c. healthcheck.** A command the engine runs *inside* a container on a repeating
interval to decide if it is healthy. You define it; you choose what "healthy" means.
Without it, the engine only knows the container is *running*, not whether it can serve.

**d. depends_on + condition.** `depends_on` says "start this after that." The *condition*
says how long to wait:
- `service_started` — wait only until the dependency's process has started. (Default if
  `depends_on` is a plain list.)
- `service_healthy` — wait until the dependency's **healthcheck passes**. Needs (c) on the
  dependency.
- `service_completed_successfully` — wait until a one-shot container exits 0 (migration
  jobs).

The jump from `service_started` to `service_healthy` is the whole point: "started" only
means the port might be opening; "healthy" means it can answer a real query.

**e. Networks + DNS.** A *network* is a private virtual LAN the containers share. When two
services sit on the same user-defined network, the engine runs a small DNS server so they
find each other **by service name**. `auth` reaches the database at the hostname
`postgres`, not an IP. Podman does this with a resolver called `aardvark-dns`; Docker has
its own built-in one. Same result: service name = hostname.

**f. Named volumes vs bind mounts.** Both put storage into a container; they differ in
*where the data lives*.
- **Named volume** — storage the engine manages in its own area, referenced by a name
  (`pgdata`). You don't see it as a normal folder; the engine owns it. Best for data you
  want to *persist but not edit by hand* — a database's files.
- **Bind mount** — a real folder on your machine mapped straight into the container
  (`./packages/auth-service` → `/app/...`). You edit the file on your laptop, the
  container sees it instantly. Best for **live code reload in dev**.
- Both used, correctly: bind mounts for source code, named volumes for Postgres and Redis.

**g. env_file + the secrets distinction.** Two different things share the name ".env":
- The **special `.env` file** in the project folder — compose reads it to fill in
  `${VAR}` placeholders *inside the YAML itself* before anything starts.
- The **`env_file:` directive** on a service — names a file whose `KEY=VALUE` lines become
  environment variables *inside that container*.
Keeping secrets out of git: commit a template (`.env.example`) with placeholders; put the
real `.env` in `.gitignore`; never write a literal secret in the YAML. (Caveat: env vars
are visible via `podman inspect` and `/proc` — env_file is convenient, not hardened. True
secrets use a `secrets:` block that mounts files under `/run/secrets`.)
