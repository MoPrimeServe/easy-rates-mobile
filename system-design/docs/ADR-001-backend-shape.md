# ADR-001 — EasyRates Backend Shape

## Status

Accepted

> **Amendment — 2026-06-21 (api-contracts reconciliation, plan/09).** `status-service` was
> dissolved; the nine-service count is unchanged but the membership is updated:
> - **Removed:** `status-service`.
> - **Added:** `municipality-service` — inbound CRM webhook that ingests a municipal
>   resolution (sets `ObjectionStatus`, enqueues the resident notification), authenticated by
>   `X-Municipal-Webhook-Secret`; not called by the Flutter app.
> - **Absorbed into `objection-service`:** the resident-facing TRACKING & RESOLUTION routes
>   (`GET /objections/:ref/status`, `/probe`, `/escalate`, `/close`, and the MORE_INFO
>   re-upload via `/objections/:id/evidence`). The former `objection → status` synchronous
>   call is now intramodule.
> - **Absorbed into `account-service`:** `GET /account/objections` (History of Objections).
>
> Current roster (9): auth, otp, property, account, bill, objection, notification,
> **municipality**, queue-consumer. The Context list below is retained for history; §F and the
> traceability matrix reflect the amended roster.

---

## Context

EasyRates is a ratepayer portal for Emfuleni Local Municipality. Its sole consumer is a Flutter mobile application (Android-first). The product is scoped to seven process flows: **ONBOARDING**, **FIND PROPERTY**, **BILL REVIEW**, **EVIDENCE & CHALLENGE**, **SUBMISSION**, **TRACKING & RESOLUTION**, and **ACCOUNT & SETTINGS**.

These flows require nine backend services: auth, otp, property, queue-consumer, bill, objection, notification, status, and account. *(Amended 2026-06-21: `status` was later dissolved and `municipality` added — see the Amendment under Status and the traceability matrix.)* Before implementation begins, six architectural decisions must be committed so that all services share consistent infrastructure choices and no decision is re-litigated per-service.

The Flutter app is the only client. There is no web portal, WhatsApp bot, or USSD channel in Phase 1 scope. Every API contract must therefore be designed for a single mobile consumer operating over intermittent South African mobile data connections.

---

## Decisions

### A. Queue Technology

**Chosen:** BullMQ (Redis-backed)

**Rationale:**
The ONBOARDING flow's `OTP Expired / Resend` branch requires a reliable async worker to dispatch OTP jobs after the HTTP request returns 202. BullMQ is backed by the same Redis instance already required for OTP TTL and session caching — no additional broker container is needed in Podman Compose. The SUBMISSION flow's `Submit Objection → Ref Generated` transition dispatches a notification job immediately after submission; BullMQ's native TypeScript client makes this a typed, testable operation without a separate message-broker dependency.

**Rejected alternatives:**
- **RabbitMQ** — adds an AMQP broker container, CloudAMQP dependency, and a separate operational concern; unjustified for Phase 1 job volume.
- **Redis Streams** — lower-level than BullMQ; requires reimplementing retry backoff, dead-letter queues, and worker concurrency that BullMQ provides out of the box.

---

### B. OTP Delivery Product

**Chosen:** Twilio Verify API

**Rationale:**
The ONBOARDING flow contains three OTP outcome branches: `OTP Invalid`, `OTP Expired`, and `OTP Valid`. Managing TTL, attempt counting, and the `OTP Expired / Resend` transition in application code would require a dedicated Redis key per OTP record. Twilio Verify API handles TTL enforcement, per-code attempt limits, and resend natively — the service only calls Verify's check endpoint and maps the `approved` / `pending` / `expired` statuses directly to the three Figma branches. This eliminates a Redis-managed OTP delivery-state layer while keeping the `OTPRecord` table for audit history.

**Rejected alternatives:**
- **Twilio Programmable Messaging** — sends arbitrary SMS but provides no TTL, attempt counting, or expiry semantics; those would have to be reimplemented in the otp-service, adding complexity and a Redis key-management surface for the `OTP Expired` branch.

---

### C. OTP TTL and Max-Attempt Limit

**Chosen:** TTL = 10 minutes, max attempts = 5

**Rationale:**
The `OTP Expired` branch on the ONBOARDING Verify Screen appears as a distinct user-visible error state; the TTL must be long enough that residents on slow GPRS connections can receive and enter the code without triggering it inadvertently. Ten minutes is the Twilio Verify default and is standard for South African mobile banking. Five attempts prevents brute-force while accommodating fat-finger input on small screens. Exceeding 5 attempts locks the record and surfaces the `OTP Locked → Resend` branch, at which point `POST /otp/resend` creates a fresh record with a reset counter.

**Rejected alternatives:**
- **5-minute TTL** — too short for low-connectivity environments in Sebokeng/Evaton; would drive unnecessary support requests via the `OTP Expired → Contact Support` path.
- **10 attempts** — increases brute-force window beyond acceptable risk for an account that controls municipal bill disputes.

---

### D. JWT Token TTLs

**Chosen:** Access token TTL = 15 minutes, refresh token TTL = 30 days

**Rationale:**
The `Refresh Token` step in the ONBOARDING flow is a background transition — invisible to the user. A 15-minute access token TTL bounds the exposure window for a stolen token to one session interaction. The Flutter app calls `POST /auth/refresh` silently before any authenticated request; this is transparent on mobile data. A 30-day refresh token TTL means residents who use the app weekly are never forced back to the `Log In` screen. Refresh tokens are stored in the `RefreshToken` table and revoked on `POST /auth/logout`.

**Rejected alternatives:**
- **1-hour access token** — increases stolen-token exposure window without meaningful UX benefit given silent refresh.
- **7-day refresh token** — forces weekly re-login on residents who dispute a bill and then check status days later; friction in the `Tracking & Resolution` flow.

---

### E. Push Notification Provider

**Chosen:** FCM (Firebase Cloud Messaging) with APNs bridge

**Rationale:**
The `Municipality Response → Notification Dispatched` transition in the TRACKING & RESOLUTION flow must deliver a push notification to the Flutter app. Flutter's `firebase_messaging` package integrates directly with FCM; FCM bridges to APNs for iOS devices via Firebase's server infrastructure. A single provider handles both platforms without maintaining two server-side channels. The ACCOUNT & SETTINGS flow's `Notification Preferences` screen allows residents to disable push; FCM token registration is optional and gated on this preference.

**Rejected alternatives:**
- **OneSignal** — adds a third-party aggregation layer; FCM direct is simpler and free at Phase 1 volume.
- **APNs direct** — requires separate server-side certificate management for iOS; redundant when FCM already bridges to APNs.

---

### F. Architecture Pattern

**Chosen:** Modular monolith in a pnpm workspace, one container per service in Podman Compose

**Rationale:**
The seven Figma flows span nine services, but Phase 1 volume does not justify the operational overhead of independent deployments. A pnpm workspace with one package per service (`packages/auth-service`, `packages/otp-service`, etc.) enforces the module boundary in code while allowing all services to run in a single Podman Compose file. Each service is a separate container with its own port — meaning the `ONBOARDING` flow's `Sign Up → OTP Sent` transition can be traced as a real inter-service HTTP call in local dev and in the flow-walkthrough script. Services share no code except a `packages/shared` library for Zod config schemas and Prisma types.

**Rejected alternatives:**
- **True microservices** — independent CI/CD pipelines, service meshes, and distributed tracing infrastructure unjustified for a pilot-stage product.
- **Single process monolith** — a single Express app with nine routers destroys the service boundary enforced by the Figma flow ownership model; auth and objection code would inevitably leak across modules without a hard import barrier.

---

## Consequences

**Easier as a result of these decisions:**
- Local dev setup is one `podman-compose up` command; no external broker or cloud dependency for OTP delivery in dev (MinIO replaces Azure Blob, Redis is already required).
- The `07-flow-walkthrough.sh` script can exercise every Figma transition with a simple `curl` command and `psql` check — no mock infrastructure needed.
- BullMQ's TypeScript client and Twilio Verify's typed responses mean the queue-consumer and otp-service require minimal glue code.
- Refresh token rotation is a single table write; no distributed session store is needed.

**Harder as a result of these decisions:**
- The modular monolith pattern means services share a Postgres instance; a future split to independent databases requires a migration step.
- FCM requires a Firebase project and service-account key even in local dev (the token registration flow in `Account & Settings → Notification Preferences` cannot be end-to-end tested without it).
- Twilio Verify has a per-verification cost; test environments must use Twilio's test credentials to avoid billing.
- JWT access tokens cannot be individually revoked before the 15-minute TTL; compromise requires refresh token revocation and a separate access-token denylist (Redis) if instant revocation is ever needed.

---

## Service-to-flow traceability matrix

| Service | Figma flows it owns | Key decisions that affect it |
|---|---|---|
| **auth-service** | ONBOARDING (Sign Up, Log In, Logout) — passwordless, see ADR-002 | D (JWT TTLs), F (modular monolith) |
| **otp-service** | ONBOARDING (Verify OTP, Resend, OTP Expired branch) | B (Twilio Verify), C (TTL + attempts), A (BullMQ for async dispatch) |
| **property-service** | FIND PROPERTY (Account Found, Account Not Found, Manual Search Match/No Match) | F (modular monolith; read-only sync from billing system) |
| **queue-consumer** | ONBOARDING (OTP dispatch), SUBMISSION (notification after submit), TRACKING & RESOLUTION (status-change notifications) | A (BullMQ), B (Twilio Verify for OTP delivery), E (FCM for push) |
| **bill-service** | BILL REVIEW (View Bill, Line Items, Anomaly Banner, AI Estimate vs Actual) | F (modular monolith; AI model co-located in service) |
| **objection-service** | EVIDENCE & CHALLENGE (Create, Attach Evidence, Upload Failed), SUBMISSION (Submit → Ref Generated / Submission Error), TRACKING & RESOLUTION (Track Status, Probe, Escalate, Close, Upload Requested Docs — absorbed from former status-service) | A (BullMQ notification job on submit), F (blob storage via Azure/MinIO) |
| **notification-service** | TRACKING & RESOLUTION (Municipality Response → SMS + Push), ACCOUNT & SETTINGS (Notification Inbox) | E (FCM + Twilio Programmable Messaging for SMS), A (BullMQ for async delivery) |
| **municipality-service** | TRACKING & RESOLUTION — inbound CRM webhook (ingests municipal resolution, sets ObjectionStatus, triggers notification); no Flutter screens | E (notification triggered on resolution), F (modular monolith; webhook from clerk/back-office, `X-Municipal-Webhook-Secret` auth) |
| **account-service** | ACCOUNT & SETTINGS (Profile, Linked Properties, Notification Preferences, History of Objections) | D (JWT auth on all routes), F (modular monolith) |

---

## Reversibility

Not every decision above costs the same to undo. These three are the ones we would most
regret getting wrong, ordered by reversal cost. Each has an explicit cost, not a vague
"hard to change".

1. **Architecture pattern — modular monolith on a shared Postgres (Decision F).**
   *Hardest to reverse.* The nine services share one Postgres instance and a
   `packages/shared` library (Prisma types, Zod config schemas). Splitting any service to
   an independent database means: carving its tables out of the shared schema, replacing
   every cross-service Prisma query that currently joins across the boundary with an HTTP
   or event call, standing up a second migration pipeline, and partitioning the
   `AuditEvent` / POPIA inventory tables that today span all services. Estimated cost: a
   multi-week re-platforming effort plus a data-migration window, touching every service
   package — not a single-service change. This is why the split is deliberately *not* done
   at pilot scale; the shared-database coupling is an accepted constraint, documented so it
   is revisited *before* a tenth service is added or independent deployments are needed,
   not discovered during one.

2. **OTP delivery product — Twilio Verify (Decision B), and the keyed-hash identity gate
   (ADR-003) it sits beside.** Twilio Verify owns TTL, attempt counting, and resend
   server-side; otp-service only calls its check endpoint and maps `approved` / `pending`
   / `expired` to the three Figma branches. Moving off Verify (e.g. to Programmable
   Messaging or another provider) means **reimplementing the entire OTP state machine** —
   per-code TTL keys in Redis, attempt counters, the resend-cooldown, and the lock-out
   branch — that we deliberately chose *not* to build. Estimated cost: rebuild and re-test
   the full otp-service lifecycle (the `otp_expired` / `otp_invalid` /
   `max_attempts_exceeded` branches all change shape), roughly 1–2 weeks, plus a credential
   and number-pool migration. Adjacent and similarly costly: ADR-003's keyed-hash pepper
   (`ID_NUMBER_HMAC_PEPPER`) — rotating it cannot re-derive `User.idNumberHash` (plaintext
   was discarded at register), so a pepper change forces every registered user to re-enter
   their SA ID. The pepper is therefore treated as long-lived; rotation is a compromise-only
   event with a one-time re-verify step.

3. **Queue technology — BullMQ (Decision A).** BullMQ is Redis-backed and reuses the Redis
   instance already required for sessions/caching, so worker definitions, retry/backoff,
   dead-letter queues, and concurrency are all expressed in its TypeScript API. Switching
   to RabbitMQ after launch requires rewriting every worker and producer definition
   (OTP dispatch, post-submission notification, status-change notification), adding an AMQP
   broker container to the Podman Compose topology, and re-establishing retry/DLQ semantics
   in the new broker. Estimated cost: ~3 days of work plus a deployment window to introduce
   the broker container. Less costly than the two above because the queue boundary is
   narrow (a handful of job types) and no schema or PII migration is involved — but still a
   coordinated, broker-swapping change rather than a config tweak.

---

## Flutter Integration Notes

This section is self-contained — a mobile developer can orient from it without reading the
per-service contracts. Field names below are **camelCase**, matching `api/conventions.md`
and the actual contracts (the response envelope is always `{ data, error }`).

- **JWT token refresh via a Dio interceptor.** The 15-minute access token (Decision D) is
  held **in memory only**; the 30-day refresh token lives in `flutter_secure_storage`. A
  Dio interceptor catches `401`, calls `POST /auth/refresh` transparently, retries the
  original request, and only surfaces a re-login if the refresh token itself is rejected.
  Refresh is silent — never a user-visible screen transition.

- **Error handling switches on `error.code`, not on HTTP status alone.** Every error
  response carries `error.code` (a stable string) in the envelope. The OTP branches in
  particular map to distinct screen states: `otp_expired` (HTTP 410) → OTP Expired / Resend;
  `otp_invalid` (HTTP 422, with `error.details.attemptsRemaining` / `maxAttempts`) → inline
  "X attempts remaining"; `max_attempts_exceeded` (HTTP 429) → Resend. Do not branch UI on
  the status code alone — `429` is also rate-limiting elsewhere; the `code` string
  disambiguates.

- **OTP countdown values are integers in the response — never hardcode them.** OTP
  initiation responses carry `ttlSeconds` (600) and `resendCooldownSeconds` (30). Drive the
  expiry countdown from `ttlSeconds` and the resend-button cooldown from
  `resendCooldownSeconds` as returned; treat the numbers above as defaults the server can
  change, not Flutter constants.

- **File upload is constrained by fields in the objection evidence contract.** The objection
  detail response exposes `maxFileSizeBytes` (10485760 = 10 MiB) and `acceptedMimeTypes`
  (`["application/pdf","image/jpeg","image/png"]`). Use these to constrain the `file_picker`
  **before** upload; evidence is sent as `multipart/form-data` and is magic-byte validated
  server-side, so the returned `mimeType` is the *detected* type, not the client-declared
  header — surface server rejections, do not assume the client check is authoritative.

- **In-app inbox vs push notifications are two different paths.** In-app history is fetched
  via `GET /notifications` (paginated, newest-first, carries a `read` boolean). Push delivery
  (FCM with APNs bridge, Decision E) is asynchronous and does **not** flow through the REST
  API — a push deep-links into the app, and the same event also appears as a row in
  `GET /notifications`. Register the FCM token only when the Notification Preferences screen
  has push enabled.

---

## References

The decisions above are extracted from the system-design working documents; this ADR is the
hardened commitment, those are the rationale sources.

- `docs/envelope.md` — scale and load envelope (Phase 1 volume that justifies the modular
  monolith and BullMQ over heavier brokers).
- `docs/queue-topology.md` — worker patterns and failure behaviour behind Decision A (BullMQ).
- `docs/twilio-integration.md` — Twilio Verify lifecycle, status mapping, and the OTP error
  codes behind Decisions B and C.
- `docs/nfr.md` — NFR targets and the Azure hosting / pilot-tier scaling path.
- `docs/data-model.md` (and `docs/data-model/`) — PK type, soft-delete, audit-log approach,
  index strategy behind the shared-schema constraint in Decision F.
- `docs/security.md` (and `docs/security/`) — POPIA field controls, rate-limit middleware,
  file-upload validation.
- `docs/service-map.md` — bounded contexts and service ownership feeding the traceability
  matrix.
- `podman-compose.skeleton.yml` — the container-per-service runtime topology of Decision F.
- `api/conventions.md` — camelCase, the `{ data, error }` envelope, pagination, date format
  (the API conventions the Flutter Integration Notes depend on).
- `api/*.md` — the per-service contracts (auth, otp, property, bill, objection, notification,
  municipality, account) that realise these decisions; ADR-002…ADR-005 refine specific routes
  within them.
