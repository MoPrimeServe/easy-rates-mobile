# ⚙️ Node.js Production Hardening

## Background

⛔ BLOCKED[Gate] — requires parent plan/07-security-design.md LEARN task
(production hardening scope understood — this plan operationalises it for Node.js).

The Node.js production hardening checklist is the complement to plan/04 (OWASP
cross-check). OWASP checks the design; this plan checks the runtime configuration.
A Node.js server without `helmet.js`, without startup env validation, and with an
open CORS policy is exploitable even if the application logic is correct.

## Description

Define the Node.js production environment hardening configuration: `helmet.js`
security headers, HTTPS enforcement, environment variable validation at startup
(`zod` or `envalid`), CORS configuration for the Flutter mobile client, and CSP
headers where applicable.

## Purpose

To answer: "what Node.js production configuration mistake would be most exploitable
on day one of the pilot — and how do we catch it before the service is deployed?"

## Goal

`easy_rates/system-design/docs/security/node-hardening.md` — a checklist of every
hardening item with Pass / Accept/Mitigate status and the configuration value or
reasoning; ready to be implemented directly from this document.

## Tasks

- [x] ✅ THINK `/socratic "What Node.js production configuration mistake is most
  commonly exploited in the wild — and does EasyRates have a specific reason to
  be more or less vulnerable than a typical Node.js service? What is the one
  hardening step that, if skipped, would be most likely to be exploited in the
  first 30 days of the pilot?"`
  Done when: the highest-priority hardening item is identified with a one-line
  justification; the reasoning is specific to EasyRates (municipal data, POPIA
  obligations, pilot user base).

- [x] ✅ LEARN `/unpack "helmet.js — which HTTP security headers it sets by default
  (Content-Security-Policy, X-Frame-Options, X-Content-Type-Options, HSTS,
  Referrer-Policy, etc.), which headers are on by default vs opt-in, and how to
  configure helmet for an Express app that serves a Flutter mobile client (no
  browser, so some browser-specific headers may be irrelevant); zod and envalid —
  how to validate required environment variables at Node.js startup and crash fast
  with a clear error if a required variable is missing or malformed; CORS
  configuration for a Flutter mobile client (which origins, which methods, which
  headers, and whether credentials:true is needed for JWT in cookies vs Authorization
  header)"`
  Done when: you can write a helmet configuration for a Node.js/Express app from
  memory; you can write a zod/envalid startup validation block that crashes the
  process if JWT_SECRET is missing.

- [x] ✅ CHECKLIST Walk through the following hardening items. For each, state
  the configuration and the reason:
  a. helmet.js: Install and configure. State which headers are enabled. Note
     which helmet defaults may need adjustment for a Flutter mobile client
     (e.g. CSP may be irrelevant if the client is purely native, not WebView).
  b. HTTPS: State whether the Node.js service handles TLS termination directly
     or delegates to a reverse proxy / Azure App Service ingress. If delegated,
     confirm that HTTP traffic is redirected to HTTPS at the proxy layer and that
     the Node.js service is protected from receiving plain HTTP from external clients.
  c. Startup env validation: Use `zod` or `envalid` to validate all required
     environment variables at startup. List the required variables:
     NODE_ENV, PORT, DATABASE_URL, REDIS_URL, JWT_SECRET, JWT_REFRESH_SECRET,
     JWT_ACCESS_TTL_SECONDS, JWT_REFRESH_TTL_DAYS, ALLOWED_ORIGINS, TWILIO_*.
     The process must crash immediately if any required variable is missing or
     fails format validation — no partial startup.
  d. CORS: Configure `cors` middleware. `ALLOWED_ORIGINS` from the environment;
     for a Flutter mobile client making REST calls with an Authorization header,
     state whether `credentials: true` is needed and why (JWT in Authorization
     header does not need CORS `credentials: true` — only cookies do).
  e. CSP headers: State whether CSP is relevant for a purely native Flutter client
     with no WebView. If the app has any in-app browser or WebView component,
     CSP must be configured. Document the decision.
  f. NODE_ENV=production: Confirm this is set in the deployment environment.
     Express (and many middleware libraries) switch to production mode, which
     disables stack traces in error responses, enables caching, and disables
     development-only features.
  g. Error response sanitisation: Confirm that stack traces are never returned
     in API error responses in production. The error envelope returns
     `{ "data": null, "error": { "code": "...", "message": "..." } }` — no
     `stack` field, no file paths.
  Done when: all 7 items have a status (Pass / Accept/Mitigate) and a
  configuration value or justification.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/security/node-hardening.md`:
  One section per checklist item; configuration value or code snippet for each;
  Pass / Accept/Mitigate status.
  Done when: all 7 items documented; every Accept/Mitigate has a trigger for
  when it would become a Pass requirement.

- [x] ✅ VERIFY Walk plan/05-nfr.md and confirm that the hardening decisions are
  consistent with the NFR targets (e.g. HTTPS requirement, 99.9% uptime target
  is compatible with the startup crash-on-invalid-env approach — misconfigured
  deployments should fail fast rather than start up with insecure defaults).
  Done when: no contradiction between node-hardening.md and nfr.md;
  any tension is documented and resolved.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "what would be exploited in the first 30 days"
   framing forces prioritisation of hardening items by actual risk, not by default
   order in a checklist.
   alt: `/unpack` ✅ — `helmet.js` configuration and `zod`/`envalid` startup
   validation if either is unfamiliar.

## Engagement Instructions

Pass condition: all 7 checklist items have a Pass / Accept/Mitigate status.
Pass condition: `helmet.js` configuration specifies which headers are enabled.
Pass condition: CORS configuration states whether `credentials: true` is needed
and why (with reference to Authorization header vs cookie auth).
Pass condition: startup env validation lists all required environment variables
by name; crash-on-missing behaviour is explicitly stated.
Pass condition: error response sanitisation confirms that stack traces are never
returned in production responses.
Pass condition: every Accept/Mitigate item has a trigger for when it would
require a full Pass control.
