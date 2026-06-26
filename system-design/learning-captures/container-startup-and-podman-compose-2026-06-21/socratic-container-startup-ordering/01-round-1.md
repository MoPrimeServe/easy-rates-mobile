# Round 1 — refining the framing

**Contract stated:** refine over a few rounds; each turn separates what's solid,
what needs work, and what's off, and probes one layer deeper. `compile` produces the
definitive walkthrough. Note made that the user handed *questions*, not a position —
so this round refines the framing, because how the question is built carries a
load-bearing assumption.

## Where you're right

Three instincts, locked in:

1. **There's a dependency chain, not a flat set.** The Flutter app talks to one
   container, which talks to others. Right to think "what must be up *before* the
   call resolves."
2. **Health-check behavior and developer experience are coupled.** The failure modes
   of a health check (slow, flapping, wrong) are themselves a DX problem, separate
   from whether the app code is correct. Orchestration is a source of bugs, not just
   plumbing.
3. **Startup-ordering bugs are a distinct, nastier class.** Singling them out as
   "hardest to diagnose" is correct — for a reason not yet named.

## Where you need guidance

**The load-bearing assumption: "the minimum set of containers" is phrased as a fixed
property of the system. It isn't. It's a property of the specific endpoint you call.**

- `GET /healthz` (touches nothing) → minimum set is **just the API container**.
- `POST /auth/login` → API **+ database**.
- An account-reconciliation or AI-assisted query → API **+ database + Qdrant + Ollama**
  (and LangGraph if it orchestrates).

"Minimum set" has no single answer until you name the call. The *first* call the app
makes on boot determines which containers you're gated on.

**Second: the Flutter app is not in the set.** It's the client, on a device/emulator,
not a container whose health you orchestrate. Don't let it into the dependency graph.

**Third: when you say "healthy," healthy by what signal?** Three, not the same thing:
- process is running,
- TCP port is open,
- the service is actually ready to serve a correct response.

The gap between #2 and #3 is where the "hardest to diagnose" bugs live.

## Where you're factually wrong

Nothing asserted yet — the user asked rather than claimed, so no misconception to
land. Section skipped honestly. (A latent trap about what `depends_on` guarantees
was left for the user to walk into.)

## Probing questions (end of round)

1. What is the *actual first* API call the Flutter app fires on launch — the real
   one, in the current build? (Token refresh, remote config, dashboard fetch?) It
   fixes the minimum set.
2. When a container is "healthy," which of the three signals is the health check
   testing — and which one does the calling container actually *need* to be true?
