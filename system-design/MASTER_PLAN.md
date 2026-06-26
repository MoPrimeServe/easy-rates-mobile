# EasyRates Mobile App — System Design

## Mission

Decide the backend shape — bounded services, queue topology, container layout,
and API surface — for all seven EasyRates mobile process flows (Onboarding,
Find Property, Bill Review, Evidence & Challenge, Submission, Tracking &
Resolution, Account & Settings). Produce a hardened ADR and screen-traceable
API contracts that a developer can build against without further discovery.
Every design choice is derived directly from the Figma process flows; design
and backend stay in full alignment.

This scope serves the **Flutter mobile app exclusively** (iOS/Android). The
WhatsApp bot is a separate channel and is out of scope here. The runtime is
Node.js (TypeScript); Django/DRF references in child plans are stale and
must be replaced before ADR-001 closes.

## Objectives

1. Figma flows ingested — all seven diagrams extracted into a structured screen
   inventory; every screen, state, decision point (pink diamond), and transition
   documented as the sole source of truth for all downstream decisions.
2. Service boundaries drawn — bounded contexts defined (Auth, OTP,
   Property/Account, Bill, Objection, Notification); each screen state and
   transition mapped to its owning service.
3. Queue topology decided — which flows are async, which queue technology
   (RabbitMQ / Redis Streams / BullMQ), producer/consumer per service; decision
   in ADR-001.
4. Twilio integration pattern decided — direct SDK call vs queue consumer; OTP
   TTL, max-attempt limit, resend flow, and all error states.
5. Architectural pattern and NFRs decided — monolith vs modular monolith vs
   microservices; cloud/hosting approach; user-scale, latency, and caching
   constraints; all resolved and documented before ADR-001 closes.
6. Container topology decided — one container per service boundary; Podman
   Compose skeleton with networks, volumes, and health-check strategy per
   service.
7. API surface designed — HTTP verb, path, request/response shape, and error
   codes per screen transition; contract docs cover all six process flows.
8. ADR hardened — ADR-001-backend-shape.md written; every decision traceable
   to a Figma screen or transition.

## Goals

- G0  `easy_rates/system-design/docs/screen-inventory.md` — table: screen
  name, states, user-facing data fields, triggering event, service owner;
  covers all seven diagrams with zero unaccounted screens.
- G1  `easy_rates/system-design/docs/service-map.md` — bounded contexts +
  ownership matrix; which screen transition calls which service endpoint.
- G2  `easy_rates/system-design/docs/queue-topology.md` — queue names,
  producers, consumers, message schemas, retry policy; technology decision
  documented.
- G3  `easy_rates/system-design/docs/twilio-integration.md` — integration
  pattern, OTP TTL, max-attempt limit, resend flow, error states (expired /
  invalid / max-attempts-exceeded).
- G4  `easy_rates/system-design/docs/nfr.md` — non-functional requirements:
  user scale, latency targets, read/write ratio, caching strategy, CDN
  decision, cloud vs on-prem; no open NFR questions remaining when this doc
  closes.
- G5  `easy_rates/system-design/podman-compose.skeleton.yml` — services,
  ports, networks, volumes (.env placeholders only; no real credentials).
- G6  `easy_rates/system-design/api/` — one markdown file per service (auth,
  otp, property, bill, objection, notification) with all routes,
  request/response schemas, and error codes.
- G7  `easy_rates/system-design/docs/ADR-001-backend-shape.md` — complete ADR
  covering O3–O8 decisions; every decision traceable to a Figma screen or
  transition.

## Expected Outcome

A backend blueprint precise enough that a developer reading only
`easy_rates/system-design/` can implement each service independently and
integrations will fit together without coordination overhead. The Figma process
flows are the authoritative specification — no screen state or transition is
left unaccounted for in the API surface, and no endpoint exists without a
corresponding screen state.

## Definition of Done

1. ✅ Every screen in all seven Figma flows appears in `screen-inventory.md` with a
   service owner and owning endpoint — zero unaccounted screens.
2. Every decision point (pink diamond) maps to a specific service endpoint and
   documented decision branch.
3. ✅ NFRs resolved in `nfr.md` — user-scale, latency, cloud/hosting, caching —
   no open questions.
4. ADR-001 written and committed; all objectives O3–O8 covered.
5. Queue technology chosen; `queue-topology.md` complete with
   producer/consumer assignments and retry policy.
6. `podman-compose.skeleton.yml` validates without errors (skeleton only).
7. API contract review passes: zero orphan screen states and zero orphan
   endpoints.
8. ✅ `twilio-integration.md` covers OTP TTL, max attempts, resend flow, and all
   error states.

## JIRA Binding

to be added — read from here once populated

## Sub-Scopes

- ✅ [plans/security/](plans/security/MASTER_PLAN.md) — "Complete security design: POPIA, JWT, rate limits, upload validation, OWASP hardening"
- ✅ [plans/data-model/](plans/data-model/MASTER_PLAN.md) — "Complete Node.js/TypeScript data model (Prisma) for all entities serving the Flutter mobile app"
- ✅ [plans/api-contracts/](plans/api-contracts/MASTER_PLAN.md) — "Complete HTTP API surface for the Flutter mobile app — all 9 service contracts + orphan audit"

## Plans

- ✅ [00-figma-ingest.md](plans/00-figma-ingest.md) — ingest Figma PDF; produce screen-inventory.md (hard gate for all plans)
- ✅ [01-service-boundaries.md](plans/01-service-boundaries.md) — bounded contexts (Node.js/TypeScript services), sync/async split, service-map.md
- ✅ [02-envelope.md](plans/02-envelope.md) — back-of-envelope capacity planning; feeds NFR, data model, and container sizing
- ✅ [03-queue-topology.md](plans/03-queue-topology.md) — queue technology decision, task topology, failure scenarios
- ✅ [04-twilio-integration.md](plans/04-twilio-integration.md) — Twilio product choice, OTP lifecycle parameters, error codes
- ✅ [05-nfr.md](plans/05-nfr.md) — latency targets, availability, caching, CDN, hosting tier; all measurable
- ✅ [06-data-model.md](plans/06-data-model.md) — ERD, Prisma model fields, indexes, design decisions, migration strategy
- ✅ [07-security-design.md](plans/07-security-design.md) — POPIA inventory, JWT model, rate limits, upload validation, OWASP
- ✅ [08-container-topology.md](plans/08-container-topology.md) — Podman Compose skeleton, health checks, .env.example
- ✅ [09-api-contracts.md](plans/09-api-contracts.md) — HTTP contracts per service (TypeScript interfaces), Figma traces, orphan audit
- ✅ [10-adr.md](plans/10-adr.md) — ADR-001 hardened and committed; reversibility stated; Flutter integration notes self-contained
