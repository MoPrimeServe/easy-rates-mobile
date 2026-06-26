# 5. A concrete example — the three core services, traced

The minimum-viable slice of the EasyRates file: `postgres`, `redis`, `auth`. The real
shape, and what each line does.

```yaml
networks:
  easyrates_net:                 # the private LAN; gives DNS-by-service-name
    driver: bridge

volumes:
  pgdata:                        # named volume — engine-managed DB storage

services:
  postgres:
    image: postgres:16-alpine
    networks: [easyrates_net]
    env_file: .env               # POSTGRES_USER/PASSWORD/DB land as env vars in the container
    volumes:
      - pgdata:/var/lib/postgresql/data   # named volume -> data survives `down`
    healthcheck:                          # <-- a healthcheck block, from memory:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
      interval: 5s
      timeout: 3s
      retries: 10
      start_period: 10s

  auth:
    image: tbd/auth-service:latest
    networks: [easyrates_net]
    env_file: .env
    volumes:
      - ./packages/auth-service:/app/packages/auth-service   # bind mount -> live reload
    depends_on:                  # <-- a depends_on health condition, from memory:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "node", "-e", "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 30s
```

Trace `podman-compose up` cold:

1. `easyrates_net` is created; its DNS starts. From now on `auth` can resolve the
   hostname `postgres`.
2. `pgdata` volume is created (first run) or reused (later runs).
3. `postgres` starts — it has no `depends_on`. `auth` does **not** start yet; it's blocked
   at its gate waiting for `postgres` *and* `redis` to be `healthy`.
4. Inside `postgres`, the engine runs `pg_isready -U app -d easyrates` every 5s. The `$$`
   became a single `$` inside the container, so the shell there reads the real
   `POSTGRES_USER` env value (`app`). First 10s of failures are ignored (`start_period`).
5. `pg_isready` returns 0 → `postgres` flips `starting → healthy`. (Same for `redis` with
   `redis-cli ping`.)
6. **Both dependencies healthy → the gate opens → `auth` starts.**
7. `auth` connects to the DB using `DATABASE_URL` from `.env`, which points at host
   `postgres:5432` — resolved by the network's DNS to the postgres container.
8. The bind mount means editing `auth-service` source on the laptop changes the code the
   container runs, no rebuild.

The note on the `$$`: in step 4, if you had written a single `$`, compose would have
tried to interpolate `$POSTGRES_USER` *at parse time* from your shell and likely
substituted nothing. `$$` defers it to the container's runtime. That one detail is the
most common Podman/Docker compose healthcheck bug.

---

## The three things to write from memory (the Done-when)

**Healthcheck block:**
```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
  interval: 5s
  timeout: 3s
  retries: 10
  start_period: 10s
```

**depends_on with a health condition:**
```yaml
depends_on:
  postgres:
    condition: service_healthy
```

**Named volume (declare at top level, mount in the service):**
```yaml
volumes:
  pgdata:                       # top-level declaration
# ...inside the service:
    volumes:
      - pgdata:/var/lib/postgresql/data
```

If reproducible without looking, the LEARN task is genuinely `verified`, not just
`stated`.
