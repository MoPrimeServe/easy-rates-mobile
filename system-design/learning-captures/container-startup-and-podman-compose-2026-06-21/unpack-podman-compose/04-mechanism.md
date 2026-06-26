# 4. The mechanism that matters (no math here)

There's no math in compose. The load-bearing mechanism is a small **state machine per
container**, and `service_healthy` keys off it:

```
created → starting ──(healthcheck passes)──→ healthy
                  └──(healthcheck fails N×)──→ unhealthy
```

- During **`start_period`**, failing checks **don't count** — they don't push toward
  `unhealthy` and don't trigger restarts. This is the grace window for migrations and
  pool warmup.
- After `start_period`, the engine needs `retries` consecutive failures (each `interval`
  apart, each bounded by `timeout`) before flipping to `unhealthy`.
- A `depends_on: condition: service_healthy` dependent is released **only on the
  `healthy` transition** — not on `starting`.

This is exactly the socratic point made concrete: `service_started` releases at
`created→starting`; `service_healthy` waits for `starting→healthy`. The gap between those
two states is where the 500-then-retry race lived.
