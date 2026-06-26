# Round 3 — depends_on gates the wrong boundary

**User's answer:** "I dont know." The round delivers the crux directly.

## The answer

**What `depends_on: service_healthy` does *not* guarantee: it orders *container starts*,
not *application readiness* — and it knows nothing about the client.**

`depends_on: db: condition: service_healthy` promises exactly one thing: *the `db`
container reported healthy at the instant the `api` container was allowed to start.*
That's it. It says nothing about:

- **The api's own warmup.** Once `api` is allowed to start, it still has to boot — load
  the framework, run entrypoint migrations, open its connection pool. During that window
  the port may already be open (row 2 vs row 3), so the app's first call lands *mid-boot*
  and 500s. The retry works because the boot finished in the gap. `depends_on` gated
  `api` on `db` — but nothing gated **the app's first request on `api` being ready.**
- **The client at all.** The Flutter app isn't in the compose graph. `depends_on` cannot
  reach it. The app fires the instant it can reach the port — earlier than "ready."

One-line answer: *`depends_on` gates the wrong boundary.* It synchronizes container A
starting against container B being healthy, but the actual race is *app calling api*
against *api being ready* — a boundary compose doesn't model.

## Why this is the hardest bug to diagnose (the Q4 answer)

Every property that defeats debugging:

1. **It self-heals on retry.** By the time you SSH in and run the call by hand, the
   warmup window has closed and it works. *It won't reproduce when you go looking.*
2. **It's timing-dependent, so environment-dependent.** A fast laptop closes the warmup
   window before the app's first call; CI or a loaded box doesn't. "Works on my machine"
   is *literally true* and tells you nothing.
3. **Every component reports success.** `docker ps`: running. Healthcheck: green. Logs: a
   lone 500 with no stack trace pointing at orchestration, because the code is fine — it
   was just called 200ms too early. Nothing is "broken," so there's nothing to fix by
   inspection.

That triad — non-reproducing, environment-sensitive, everything-reports-healthy — is the
signature of the startup-ordering bug class. Hard precisely because the system is lying
to you in good faith.

## Close

Stated this is compile-ready (the spine is covered: minimum set is per-endpoint;
"healthy" must mean ready-not-port; the killer bug is gate-the-wrong-boundary). Offered
either `compile` or a gentler next question: given the diagnosis, where would you put the
fix — in the app, in the api, or in compose? (There's a defensible case for each.)

User chose `compile`.
