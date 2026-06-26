# Compile — Container Startup Ordering & the First Successful API Call

A definitive walkthrough. By the end: why the "minimum set" is per-endpoint, why
"healthy" is a trap, why the killer bug exists, and how to force it to reproduce.

## 1. Definitions

- **Container** — an isolated running process (api, db), managed by Docker.
- **Healthcheck** — a command Docker runs inside a container on an interval to decide
  if it's `healthy`/`unhealthy`/`starting`. You write it; its quality is on you.
- **The three readiness signals** — increasing strength:
  1. *Process up* — the container didn't crash.
  2. *Port open* — it accepts TCP connections.
  3. *Actually ready* — it returns a *correct* response *and* its own dependencies are
     reachable.
- **`depends_on`** — compose directive declaring start-order. With
  `condition: service_healthy`, container A doesn't start until B reports `healthy`.
- **Client** — the thing making the call. Here, the Flutter app, on a device/emulator.
  **Not a container.** Not in the compose graph. Nothing in compose can gate it.
- **First API call** — the request the app fires before a human interacts: a session
  refresh, a config fetch, or the login POST.
- **Minimum set** — the containers that must be at signal #3 for *one specific endpoint*
  to return a correct response. **A property of the endpoint, not the system.**
- **Startup-ordering bug** — a failure caused by a call arriving before its dependency is
  at signal #3. Self-heals on retry.

## 2. Brief background

`docker compose up` starts containers roughly together. `depends_on` lets you impose
order. But order-of-*start* is not order-of-*readiness*, and the client lives outside the
whole system. Almost every "works on my machine, 500s in CI" boot bug lives in those two
gaps.

## 3. Components (the stack)

- **`app`** — Flutter client. Fires the first call. Outside compose.
- **`api`** — Django+DRF (or Node). The one container the app talks to directly.
- **`db`** — Postgres locally, or **Azure SQL** (managed cloud — *not a container at all*,
  a network dependency you don't control the startup of).
- **`qdrant`** — vector store. In the set only for AI/recon endpoints.
- **`ollama`** — local LLM. In the set only for AI endpoints.
- **`langgraph`** — orchestration. In the set only when an endpoint runs an agent flow.

Dependency graph for one call:

```
app ──HTTP──▶ api ──▶ db
                  └──▶ qdrant ──▶ ollama   (only AI endpoints)
                  └──▶ langgraph           (only agent endpoints)
```

## 4. Step-by-step pipeline (life of the first call)

1. **`docker compose up`** — Docker schedules all containers.
2. **`db` starts**, runs init, eventually passes its healthcheck → `healthy`.
3. **`depends_on` releases `api`** — only now is `api` allowed to start.
4. **`api` boots** — loads framework, **runs migrations**, opens its connection pool.
   *The port opens partway through this (signal #2 reached before signal #3).*
5. **`api` passes its healthcheck** → `healthy`. (If the check is port-based, this fires
   too early — during step 4, not after it.)
6. **The `app` fires its first call** — independently, on its own clock. Nothing gates
   this against step 5.
7. **Resolution** — if `api` reached signal #3 first: 200. If the call arrived during
   step 4: **500**, then 200 on retry.

The bug is the ordering of steps 6 and 4. Compose controls 2→3. It controls *nothing*
about 6.

## 5. Concrete example, traced end to end

Stack on a loaded CI box. First call is `GET /me` (session restore). `api` is Django;
entrypoint runs `migrate` then `gunicorn`.

```
t=0.0s  compose up. db + api containers scheduled.
t=0.5s  db: process up, port open, init running.        (signal #2)
t=3.0s  db healthcheck (real query) → healthy.          (signal #3)
t=3.0s  depends_on releases api. api entrypoint begins.
t=3.1s  api: `python manage.py migrate` starts...
t=3.1s  app splash finishes, fires GET /me  ◀── THE FIRST CALL
        ...but gunicorn isn't up yet → connection refused.
        app's http client retries in 500ms.
t=3.6s  migrate still running on the loaded box.
        gunicorn not up. retry → refused again.
t=4.0s  migrate finishes. gunicorn binds the port.      (api signal #2)
t=4.0s  api port-based healthcheck → healthy  ◀── LIES: pool not warm
t=4.1s  app's 2nd retry lands. gunicorn up, but the first
        worker's DB connection pool is still opening.
        → 500 (OperationalError).
t=4.6s  app's 3rd retry. pool warm. api at signal #3.
        → 200. App loads. User sees nothing wrong.
```

Postmortem next morning: `docker ps` all green. Healthchecks green. One 500 in the logs,
no orchestration fingerprint. Run `GET /me` by hand — 200, instantly. **Nothing
reproduces.** That is the whole bug.

On the dev's fast laptop, `migrate` + pool warmup finish at t=3.4s, the first call lands
at t=3.5s, clean 200. The bug is invisible there. Same code. Same compose file.

## 6. Per step — build it from first principles

**Step 2–3 (db healthy, the real way).** A healthcheck that runs an actual query, not a
port poke:
```yaml
db:
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U app -d app || exit 1"]
    interval: 2s
    timeout: 3s
    retries: 15
    start_period: 5s   # grace window: failures here don't count
```
(Azure SQL note: if `db` is managed cloud, there's no container to healthcheck. The
`api` must treat the DB as a flaky network dependency — retry-with-backoff on connect —
because compose can't gate on it at all.)

**Step 4 (api boot) + Step 5 (honest api healthcheck).** An endpoint that proves signal
#3 — runs a trivial DB query and returns 200 only after the pool is live:
```python
# urls.py  — the readiness endpoint
def readyz(request):
    from django.db import connection
    with connection.cursor() as c:
        c.execute("SELECT 1")
    return JsonResponse({"ready": True})
```
```yaml
api:
  depends_on:
    db: { condition: service_healthy }
  healthcheck:
    test: ["CMD-SHELL", "curl -fsS http://localhost:8000/readyz || exit 1"]
    interval: 2s
    timeout: 3s
    retries: 30
    start_period: 10s   # covers migrate + warmup
```

**Step 6 (the client — the gap compose can't close).** The app is outside compose, so the
only place to defend this boundary is in the client — bounded retry-with-backoff on
connection-refused and 503:
```dart
// app side — make the first call resilient, because nothing else can
Future<Response> bootCall() => retry(
  () => dio.get('/me'),
  retryIf: (e) => e.isConnectionError || e.response?.statusCode == 503,
  maxAttempts: 5,
  delay: (n) => Duration(milliseconds: 300 * (1 << n)), // 0.3,0.6,1.2,2.4s
);
```
And make the api **return 503, not 500, while warming** — a 503 says "not ready, retry
me"; a 500 says "I'm broken, don't." That status-code choice turns an undiagnosable error
into a self-correcting handshake.

## 7. Per step — a small concrete exercise

1. **Prove signal #2 ≠ #3.** Run Django with a 10-second `time.sleep()` at the top of the
   migration entrypoint. Curl the port during that window. Watch the connection succeed
   (port open) while a real endpoint 500s. You've *seen* the gap.

2. **Build the honest healthcheck.** Add `/readyz`. With the sleep still in place, watch
   `docker ps` show `health: starting` for the full 10s, then flip to `healthy`. Compare
   against a port-based check, which flips green immediately. Two checks, same container,
   different truths.

3. **Force the killer bug to reproduce on demand** (the payoff). Add an artificial 8s
   warmup to the api *and* remove the app's retry. Boot the stack and immediately fire the
   first call (`curl` standing in for the app):
   ```bash
   docker compose up -d && curl -s -o /dev/null -w "%{http_code}\n" localhost:8000/me
   # → 000 (refused) or 500.  Wait 10s, curl again → 200.
   ```
   You've turned the non-reproducing CI ghost into a one-command demo. *The core skill:*
   startup-ordering bugs are beaten by manufacturing the timing window, not by staring at
   green dashboards.

4. **Close it three ways and compare.** Fix the same bug (a) in compose (`start_period` +
   `/readyz`), (b) in the api (return 503 while warming), (c) in the app (retry-with-
   backoff). Re-run exercise 3 after each. Only (c) covers the *client* boundary — (a) and
   (b) shrink the window but the app is still outside the graph. The robust answer is
   **all three**.

## The whole thing in three sentences

The minimum set of containers is a property of the *specific endpoint*, not the system —
`GET /healthz` needs only `api`, `GET /me` needs `api`+`db`, an AI query needs
`api`+`db`+`qdrant`+`ollama`. "Healthy" must mean *ready to serve* (signal #3), because a
port-open check (#2) lies during boot and invites the 500-then-retry race. And the race
is the hardest bug to diagnose because `depends_on` gates the wrong boundary —
container-start against container-health, never *app-call against api-ready* — so it
self-heals on retry, only bites on slow/loaded machines, and every dashboard reports
green while it happens.
