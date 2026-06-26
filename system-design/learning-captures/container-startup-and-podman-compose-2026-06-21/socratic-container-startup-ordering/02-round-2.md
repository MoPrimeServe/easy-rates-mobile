# Round 2 — first call discovery + the three signals

**User's answer:** "1. Not sure  2. healthy?" — both honest non-answers. The round
hands the user the tools to answer each, rather than answering over them.

## Where you're right

Only this, but it counts: didn't bluff. "Not sure" about the first call and "healthy?"
with a question mark *is* the correct posture — both are genuinely underspecified, and
pretending otherwise is how the race conditions get shipped.

## Where you need guidance

**(1) How to find your first API call — determinable in two minutes.** The first call
is whatever the app fires before a human touches it. Almost always one of three shapes:

- App opens straight to a **login screen** → first call is `POST /auth/login` on submit.
  (Needs API **+ DB**.)
- App **restores a session** on launch — checks stored token, refreshes it → first call
  is `POST /auth/refresh` or `GET /me`. (Needs API **+ DB**.)
- App fetches **remote config / feature flags** on splash → `GET /config`. (Might need
  only API if config is static; needs DB if stored.)

How to know yours: open the Flutter startup path — `main.dart`, the splash/bootstrap
widget, or the app-state initializer — and find the first `http`/`dio` call. Or run the
app against a logging proxy and read the first line. Consequence: **two of the three
shapes put the database in your minimum set, one might not.**

**(2) What "healthy" means — three signals, not interchangeable:**

| Signal | What it proves | How a healthcheck tests it |
|---|---|---|
| **Process up** | the container didn't crash | `docker ps` says running |
| **Port open** | it accepts TCP connections | `curl`/`nc` to the port succeeds |
| **Actually ready** | returns a *correct* response *and* its deps are reachable | `GET /healthz` that runs a real DB query and returns 200 |

**The trap lives between rows 2 and 3.** Django's runserver (and gunicorn) **open the
port before migrations finish**. So a port-based healthcheck reports "healthy," the API
starts accepting traffic, the app fires its first call — and gets a 500 because the
tables don't exist yet. The container was "healthy" by the signal chosen; it just
wasn't the signal needed.

Resolution: **healthy must mean row 3 — ready to serve the specific call, dependencies
included — or the health check is lying to you.**

## Where you're factually wrong

Nothing — two question marks aren't a misconception. Skipped honestly.

## Probing question (end of round)

Suppose the API's healthcheck is the **good** kind (row 3 — actually queries the DB),
and `docker compose` is told `api depends_on db: service_healthy`. You start the stack
and the very first app call still 500s once, then works on retry. What's the one thing
`depends_on: service_healthy` does *not* guarantee that could cause exactly that?
