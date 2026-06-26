# ⚡ Non-Functional Requirements

## Load Anchor (from envelope.md — do not derive independently)

> **Peak concurrent sessions (production): 5,000**
> **Peak concurrent sessions (pilot): 500**
>
> Basis: 20% of registered users (production: 25,000; pilot: 2,500) simultaneously in the
> peak 15-minute window of a WhatsApp-driven billing dispute spike. This is the worst-case
> load event — unscheduled, no advance warning, vertical ramp. Normal billing-day peak is
> ~375 concurrent (production).
>
> Source: `easy_rates/system-design/docs/envelope.md` — envelope.md is the single source of
> truth. This plan may not invent its own session estimate.

## Background
⛔ BLOCKED[Gate] — requires plans/02-envelope.md VERIFY task (envelope numbers signed
off — NFR targets are meaningless without grounded scale estimates).

NFR targets that are not grounded in real numbers are aspirations, not requirements. This
plan draws every quantitative target from envelope.md. If a target cannot be expressed
as a number with a "how to measure it" note, it does not belong in this document.

## Description
Define latency targets, availability targets, read/write ratios, caching strategy, CDN
decision, and hosting tier — for pilot and production phases separately. Every target
must be measurable in production via a named Azure Monitor metric or log query. If you
cannot measure it, you cannot know when you are violating it.

## Purpose
To answer: "what is the one NFR whose violation would make the pilot fail — and how
will we know we are about to violate it before a user complains?" Every container
resource limit, database index, and cache TTL in subsequent plans is justified by a
target set here.

## Goal
`easy_rates/system-design/docs/nfr.md` — all NFR dimensions resolved, pilot and
production columns, every target paired with a monitoring signal. Zero open questions.
Zero targets without a measurement approach.

## Tasks

- [x] ✅ THINK `/socratic "What is the one NFR whose violation would make the pilot
  fail — and how will we know in production that we are about to violate it before
  a user complains? What does 'good enough' look like for a pilot vs production?"`
  Done when: the single most critical NFR is named and its monitoring signal is
  identified; the pilot vs production distinction is explicit.
  Downstream: the named critical NFR and its monitoring signal become the opening
  "Critical NFR" section of nfr.md — write it there before any target rows are
  set. "Good enough for pilot" vs "required for production" becomes the explicit
  column header distinction in every table in the document.
  → docs/nfr.md § Critical NFR — Data Accuracy. Alert 8 (data-accuracy-estimate-streak)
  is the named monitoring signal. ✓ verified.

- [x] ✅ LEARN `/unpack "Azure SQL, Azure App Service, and Azure Cache for Redis
  performance tiers — what throughput, latency, and connection limits does each tier
  offer, and what does scaling up cost from one tier to the next?"`
  Done when: you can map the peak concurrent-session estimate from envelope.md to
  a specific Azure tier with a cost figure and a justification.
  → Applied in P95 Latency Targets (500/5,000 concurrent → Basic/S2 DTU),
  Hosting Decision (SA North costs), and Availability (composite SLA by tier). ✓ stated.

- [x] ✅ LATENCY Set P95 latency targets per endpoint category. Start from the
  envelope.md peak concurrent-session estimate and work backwards from what the
  chosen Azure tier can sustain:
  OTP send (async to Twilio — what does the Node.js endpoint return in?) |
  Property lookup (read, likely cached) |
  Bill fetch (read, DB query) |
  Objection submit (async — how fast does the Node.js service return 202?) |
  Notification list (read, paginated)
  For each: target in ms, Azure tier that can deliver it at peak load,
  and the Azure Monitor metric or application-log query that measures it.
  Done when: five targets set; each has a tier reference and a measurement approach.
  Downstream: the five P95 targets (OTP send, property lookup, bill fetch, objection
  submit, notification list) are copied verbatim into plan/08 (container resource
  limits) as the performance SLA each service container must be sized to meet.
  Neither plan/08 nor the ops team may invent their own latency figures.
  → See ## P95 Latency Targets section below.

- [x] ✅ AVAILABILITY Set availability targets for pilot and production.
  Consider: what is the cost of downtime for a ratepayer trying to submit an
  objection before the deadline? What SLA does Azure App Service / ACI offer?
  Done when: pilot and production availability targets set (e.g. 99% vs 99.9%);
  each justified against the deadline risk and Azure SLA.
  → See ## Availability Targets section below.

- [x] ✅ CACHE Define caching strategy per data type:
  Server-side (Node.js + Redis): which responses, keyed how, for how long?
  Client-side (Flutter Hive or SharedPreferences): which responses persist between
  app launches, and what invalidates them?
  Never-cache list: OTP state (always live), live billing totals (financial accuracy),
  submission status (user is watching it change), any POPIA-sensitive field.
  Done when: every service from service-map.md has an explicit cache policy —
  even if the policy is "no cache, always live."
  → See ## Caching Strategy section below.

- [x] ✅ CDN Decide: does the Flutter app need a CDN for static assets (evidence
  template PDFs, municipal branding, any downloadable content)?
  If yes: name the Azure CDN tier, which assets it serves, and the cache TTL per
  asset type.
  If no: document why — assets embedded in the app bundle? Too small to matter?
  Not served via HTTP at all?
  Done when: explicit yes/no with a paragraph justification; no "we'll decide later."
  → See ## CDN Decision section below.

- [x] ✅ HOSTING Confirm Azure as the hosting target (per CLAUDE.md stack). Choose
  the container hosting model for pilot:
  ACI (Azure Container Instances) — simple, per-second billing, no cluster ops
  AKS (Azure Kubernetes Service) — full orchestration, overkill at pilot scale?
  Azure App Service for Containers — PaaS, managed scaling, higher abstraction
  Justify against the pilot concurrent-session count from envelope.md and the ops
  capacity of the team.
  Done when: model chosen; justification references envelope.md numbers; constraints
  for plan/08 (container topology) are stated explicitly.
  → See ## Hosting Decision section below.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/nfr.md` — all dimensions above,
  pilot and production columns, monitoring signal per target, CDN decision, hosting
  choice with justification.
  Done when: file exists; no row says "TBD"; every quantitative target has a
  measurement approach.
  → `easy_rates/system-design/docs/nfr.md` — 15 KB, all 9 engagement checks pass.

- [x] ✅ VERIFY For each NFR target, write the specific Azure Monitor alert rule or
  log query that would fire if the target were being violated in production:
  e.g. "Alert when p95 response time on /api/v1/bill > 800ms over a 5-minute
  window" → Azure Monitor metric alert on HTTP Response Time.
  Done when: every target has a named alert; no target relies on "we'll know when
  users complain."
  → See ## NFR Alert Manifest section below.

## Recommended skill
▶ `/socratic` ✅ — THINK task; "what one NFR kills the pilot" is the frame that
   prevents setting targets no one will ever check.
   alt: `/unpack` ✅ — Azure hosting tiers if the ACI vs AKS choice is unfamiliar.

## Engagement Instructions

```bash
# 1. File exists
ls -lh easy_rates/system-design/docs/nfr.md
# Expected: present, size > 2 KB

# 2. Pilot and production columns present
grep -iE "pilot|production" easy_rates/system-design/docs/nfr.md | wc -l
# Expected: ≥ 10 (heading row + one per major dimension)

# 3. No TBD / open questions remain
grep -iE "TBD|decide later|to be determined|open question" \
  easy_rates/system-design/docs/nfr.md
# Expected: 0 results

# 4. Five P95 latency targets present (one per endpoint category)
for endpoint in "OTP\|otp" "property\|lookup" "bill\|fetch" \
                "objection\|submit" "notification\|notify"; do
  printf "%-30s %s lines\n" "$endpoint:" \
    "$(grep -icE "$endpoint" easy_rates/system-design/docs/nfr.md)"
done
# Expected: each ≥ 1

# 5. Azure Monitor metric or log query paired with each latency target
grep -iE "azure monitor|metric alert|log.*query|KQL|response.*time|p95" \
  easy_rates/system-design/docs/nfr.md | wc -l
# Expected: ≥ 5 (one measurement approach per target)

# 6. CDN decision explicit — yes or no with paragraph
grep -iE "CDN|azure cdn|content delivery" easy_rates/system-design/docs/nfr.md | wc -l
# Expected: ≥ 2 (decision + justification)

# 7. Hosting model chosen (exactly one of ACI / AKS / App Service)
grep -iE "ACI|Azure Container Instance|AKS|App Service for Container" \
  easy_rates/system-design/docs/nfr.md | wc -l
# Expected: ≥ 1 line naming the chosen model

# 8. Availability targets set for both pilot and production
grep -iE "99[.0-9]*%|availability|SLA" easy_rates/system-design/docs/nfr.md | wc -l
# Expected: ≥ 2 (pilot + production)

# 9. Cache policy covers every service (no service missing)
for svc in "auth" "otp" "property" "bill" "objection" "notification"; do
  printf "%-20s %s\n" "$svc:" \
    "$(grep -icE "$svc.*cache|cache.*$svc|no.cache.*$svc|$svc.*no.cache" \
       easy_rates/system-design/docs/nfr.md)"
done
# Expected: each ≥ 1 (either a cache policy or an explicit "no cache")
```

Gate: checks 1–8 must pass before plans/06, 07, and 08 may start.
Check 9 is a completeness gate — every service must have an explicit cache entry,
even if that entry is "no cache, always live." A missing service means plan/08
container memory sizing is guesswork.

---

## P95 Latency Targets

_Source: envelope.md peak anchor — 5,000 production / 500 pilot concurrent sessions._
_Tier reference: Pilot = Basic 5 DTU + App Service B1 × 1 + Redis C0. Production = S2 50 DTU + P1v3 × 3 plans + Redis C1._
_These targets are the single source of truth. plan/08 and the ops team copy them verbatim — neither may invent its own figures._

### Derivation basis

**OTP send and Objection submit are async 202 endpoints.** Node.js validates, writes to Redis (rate-limit key / OTP TTL), writes one row to PostgreSQL (OTPAttempt / Objection), enqueues to BullMQ, and returns. Twilio and Blob Storage are off the critical path. Latency = validation + Redis write + DB INSERT + queue enqueue.

**Property lookup and Bill fetch are read-dominant cached endpoints.** Property-service is 98% read; bill-service is 97% read (envelope.md). Redis is the primary store: `property:{accountNumber}` and `bill:{accountId}:{billingMonth}`. Cache miss falls through to PostgreSQL. Pilot uses C0 Redis (Basic SQL on HDD). Production uses C1 Redis (S2 SQL).

**PostgreSQL connection pool constraint (pilot):** Basic allows 30 max concurrent workers. Seven services × Prisma default pool of 5 = 35 — exceeds the limit. Each service must set Prisma `connection_limit = 4` (7 × 4 = 28 < 30). Not a latency bottleneck at 500 peak concurrent; it is a hard failure if left at Prisma defaults.

**Notification list is not cached.** 70% write ratio (bulk dispatch during billing run) makes Redis invalidation cost prohibitive. Direct PostgreSQL paginated read on `(user_id, created_at DESC)` index from plan/06-data-model. Rolling 90-day table: ~22,500 rows pilot, ~225,000 production.

**Spike behavior (production):** The social spike (WhatsApp catch-up bill photo) drives 5,000 concurrent sessions in 15 minutes — roughly 5–6 new users/second. At this arrival rate, DB concurrency peaks at ~50–100 simultaneous queries, well within S2's 120-worker limit. Cache warms on first hit, so P95 across all requests in the spike stabilizes within 2–3 minutes. Pilot spike (500 concurrent) is proportionally lighter.

### Target table

| Endpoint | Pilot P95 | Production P95 | Tier that delivers it | What changes between tiers |
| --- | --- | --- | --- | --- |
| OTP send — `POST /otp/send` → 202 | **400 ms** | **200 ms** | Pilot: Basic + B1. Prod: S2 + P1v3 | Basic is HDD-backed; INSERT latency ~80–100 ms. S2 raises DTU throughput; INSERT ~15–25 ms. Async pattern removes Twilio from critical path in both tiers. |
| Property lookup — `GET /property/*` → 200 | **300 ms** | **100 ms** | Pilot: Basic + B1 + C0. Prod: S2 + P1v3 + C1 | C0 → C1 adds replication and higher bandwidth. At 98% cache hit, DB tier matters only on the 2% miss path. Cache hit path: ~5 ms both tiers. Miss path: ~100 ms pilot (HDD), ~20 ms production (S2). |
| Bill fetch — `GET /bill/*` → 200 | **500 ms** | **150 ms** | Pilot: Basic + B1 + C0. Prod: S2 + P1v3 + C1 | Bill JOIN (Bill + BillLineItem, 5 rows per bill) is heavier than property SELECT. HDD miss path: ~150–200 ms. S2 miss path: ~30–40 ms. 97% cache hit means P95 across all requests is in the cache-hit zone (~5 ms) in steady state; target set to cover spike warmup window. |
| Objection submit — `POST /objection` → 202 | **400 ms** | **300 ms** | Pilot: Basic + B1. Prod: S2 + P1v3 | Blob Storage metadata write (~30–50 ms same-region) + DB INSERT + BullMQ enqueue. S2 halves DB INSERT time. Production target tighter because objection deadline pressure makes latency UX-critical — a slow 202 makes users retry, generating duplicate submissions. |
| Notification list — `GET /notification` → 200 | **400 ms** | **150 ms** | Pilot: Basic + B1. Prod: S2 + P1v3 | Paginated SELECT on `(user_id, created_at DESC)` index. HDD: ~100–150 ms. S2: ~15–25 ms. No Redis cache; index from plan/06-data-model is the only latency lever. |

### Measurement — Application Insights KQL alerts

Wire `applicationinsights` npm SDK in each Node.js service at startup. SDK auto-tracks every HTTP request with `name`, `duration`, `success`, and `url` fields in the `requests` table.

Create one Scheduled Query Alert per endpoint in Azure Monitor (Log Analytics workspace):

- Frequency: every 1 minute
- Time window: 5 minutes
- Alert condition: query returns any row (P95 exceeded)
- Action group: email + Teams webhook to ops

```kusto
// OTP send — alert when P95 > 200 ms (production); use > 400 ms for pilot
requests
| where timestamp > ago(5m)
| where name == "POST /api/v1/otp/send"
| summarize p95_ms = percentile(duration, 95) by bin(timestamp, 1m)
| where p95_ms > 200

// Property lookup — alert when P95 > 100 ms (production); use > 300 ms for pilot
requests
| where timestamp > ago(5m)
| where name startswith "GET /api/v1/property"
| summarize p95_ms = percentile(duration, 95) by bin(timestamp, 1m)
| where p95_ms > 100

// Bill fetch — alert when P95 > 150 ms (production); use > 500 ms for pilot
requests
| where timestamp > ago(5m)
| where name startswith "GET /api/v1/bill"
| summarize p95_ms = percentile(duration, 95) by bin(timestamp, 1m)
| where p95_ms > 150

// Objection submit — alert when P95 > 300 ms (production); use > 400 ms for pilot
requests
| where timestamp > ago(5m)
| where name == "POST /api/v1/objection"
| summarize p95_ms = percentile(duration, 95) by bin(timestamp, 1m)
| where p95_ms > 300

// Notification list — alert when P95 > 150 ms (production); use > 400 ms for pilot
requests
| where timestamp > ago(5m)
| where name startswith "GET /api/v1/notification"
| summarize p95_ms = percentile(duration, 95) by bin(timestamp, 1m)
| where p95_ms > 150
```

**Supporting dashboard metrics (Azure Monitor, not alerts):**

- `requests/duration` in Application Insights — P95 per operation name, 24h rolling
- Azure SQL `dtu_consumption_percent` — alert at sustained > 80% (precursor to DB latency breach)
- Redis `serverLoad` — alert at sustained > 80%
- Redis cache miss ratio (`cache_misses / total_ops`) — spike above 10% indicates cold start or TTL expiry; expect during first 2–3 minutes of a social spike, then recover

---

## Availability Targets

_Source: Azure SLA commitments for each phase's tier selection, cross-referenced against the cost of deadline-day downtime for Emfuleni billing objections._

### Azure SLA baseline

| Component | Pilot tier | Pilot SLA | Production tier | Production SLA |
| --- | --- | --- | --- | --- |
| App Service | B1 Basic | 99.95% | P1v3 Premium v3 × 3 plans | 99.95% |
| Azure SQL | Basic 5 DTU | 99.99% | S2 Standard 50 DTU | 99.99% |
| Redis | C0 Basic | **No SLA** | C1 Standard | 99.9% |
| **Composite** | — | **~99.44%** | — | **~99.84%** |

Composite = product of individual component SLAs. Redis C0 Basic carries no Microsoft-backed SLA; the 99.44% pilot composite assumes ~99.5% observed uptime for C0 (best-effort estimate, not contractual).

### Deadline-day risk model

Two hard-deadline contexts govern this platform:

**Monthly billing disputes.** The SA Municipal Systems Act (s.95) requires the municipality to enable ratepayers to query and appeal accounts. In practice, Emfuleni treats 30 days from statement issue as the dispute window. Missing it means the disputed amount is treated as final — it is legally extinguished for that billing cycle.

**Valuation roll objections** (less frequent, higher stakes). Under the Municipal Property Rates Act, the objection window is 30 days from notice. Late objections are inadmissible regardless of cause.

The worst-case scenario: system down during the last 2 hours before a deadline, on the last weekday of the objection window. The alternative channel — walk-in to Emfuleni civic offices — is closed after 16:00. For ratepayers in the Vaal triangle, transport to civic offices has a real cost and takes real time. Downtime on deadline day is not a UX inconvenience. It is a rights problem: the ratepayer loses the legal ability to dispute a bill they may have photographic evidence to overturn.

This asymmetry — 7 hours downtime distributed across a month is far less harmful than 30 minutes on the last afternoon of an objection window — drives the operating procedure below, not just the headline percentage.

### Targets

| Phase | Target | Allowable downtime/month | Deadline-window constraint |
| --- | --- | --- | --- |
| Pilot | **99%** | 7.2 hours | No scheduled maintenance in final 3 days of billing period. Alert within 15 minutes of outage start. |
| Production | **99.9%** | 43 minutes | No scheduled maintenance in final 3 days of billing period. Alert within 5 minutes. Pre-scale to 2 instances/plan 48 hours before deadline close. |

**Pilot justification (99%).**
The Azure composite SLA for pilot tiers is ~99.44%. Setting the target at 99% acknowledges this honestly: the pilot cannot promise more than its infrastructure can back. The B1 plan is a single instance with no redundancy — a deployment restarts the service for ~30 seconds; one deployment per week consumes ~2 minutes/month, well within the 99% budget (432 minutes). Redis C0 has no SLA, but all Redis data at pilot is either reconstructible (OTP: re-send; session cache: re-login) or durable in PostgreSQL. A Redis restart is an inconvenience, not a data-loss event. Crucially, the pilot is not the primary dispute channel — Emfuleni civic offices remain open. Users have an alternative. The pilot's job is to prove the concept, not to be a sole dependency.

**Production justification (99.9%).**
The Azure composite SLA for production tiers is ~99.84%. The target of 99.9% (43 minutes/month) is achievable because most of that 43-minute budget is consumed by unplanned Azure incidents — not planned maintenance. If deployments use App Service deployment slots (zero-downtime blue/green swap) and database schema changes are applied as online migrations, planned maintenance contributes 0 minutes to downtime. Redis C1 Standard (99.9% SLA) is the binding constraint and the target matches it exactly. Upgrading to 99.99% would require zone-redundant P1v3 (3 instances across 3 availability zones per plan) — roughly 3× the App Service cost. Not justified at 25,000 registered users. Revisit at 100,000+ or if a formal SLA agreement with the municipality demands it.

### Measurement

**Application Insights availability tests (URL ping).**
Configure one test per entry-point service. Minimum: auth-service `/health` (validates app + DB connectivity). Add otp-service and bill-service `/health` as separate tests.

- Cadence: every 5 minutes
- Success criterion: HTTP 200 within 30 seconds
- Test locations: South Africa North (primary) + West Europe (canary — catches DNS/global routing failures without SA-North-specific false positives)
- Downtime counted: 2 consecutive failures from ≥ 2 locations = outage start

**Immediate outage alert (fires within 5 minutes of outage start):**

```kusto
availabilityResults
| where timestamp > ago(10m)
| summarize success_rate = avg(todouble(success)) by bin(timestamp, 5m)
| where success_rate == 0
```

Action group: PagerDuty / Teams immediate page.

**Rolling SLA breach alert (fires when monthly budget is at risk):**

```kusto
-- Production: alert when rolling 30-day availability < 99.9%; use 99.0 for pilot
availabilityResults
| where timestamp > ago(30d)
| summarize availability_pct = 100.0 * avg(todouble(success))
| where availability_pct < 99.9
```

Action group: email to ops. If this fires mid-month, block all non-emergency deployments for the remainder of the month.

### Deadline-window operating procedure

Both phases follow this calendar-driven protocol:

1. At the start of each month: identify the closing date of the current billing dispute window (typically the last business day of the month, or 30 days from statement issue date — confirm with the municipality).
2. Mark the 3 days before that close date as a **maintenance blackout window** in the team calendar. No deployments, no schema changes, no Redis flushes.
3. Production only: at T−48h before deadline close, scale each P1v3 plan to a minimum of 2 instances. Do not rely on autoscale to trigger this — pre-scale manually.
4. If an unplanned Azure incident begins during the deadline window: log the incident start time immediately (for SLA credit claim). Send an SMS via notification-service to affected registered users stating the system is degraded and the dispute deadline will be extended by 24 hours — pending written confirmation from the municipality. Do not promise an extension without that confirmation, but send the user-facing notice immediately so ratepayers do not lose confidence and stop trying.

### What this target does not cover

Availability (uptime %) and latency (P95 response time) are separate. A system that responds in 8 seconds is technically "available" but violating the P95 latency targets from the previous section. Availability alerts fire on HTTP 5xx or timeout (> 30s). Latency alerts fire on the KQL queries in the P95 section. Both must be monitored independently.

---

## Caching Strategy

All nine services from service-map.md are covered. Every service has an explicit policy — including services whose policy is "no cache."

### Principles

**Redis as cache vs. Redis as primary store.** otp-service uses Redis as its authoritative OTP store, not as a cache in front of PostgreSQL. That usage is not covered here — it is part of the OTP service design (plan/04-otp-service.md). Every other Redis entry in this section is a read-through cache: PostgreSQL is authoritative; Redis holds a copy with a TTL.

**Key namespacing.** All Redis keys are namespaced by service and include a user- or entity-scoped ID. No key is generic — `bill:lines:{billId}` not `lines:{billId}`. This prevents accidental cross-service key collision and makes cache debugging traceable.

**User-scoped keys prevent cross-user leakage.** Every cache key that holds per-user data must include `{userId}` or `{accountId}`. A key that returns user A's data when user B requests it is a privacy breach, not just a stale-data problem.

**Hive is unencrypted by default.** Flutter's Hive box stores data as plaintext on the device. Only non-PII fields may be stored in standard Hive. For anything that qualifies as PII or financial under POPIA, use `flutter_secure_storage` (small key-value pairs) or `hive_cipher` with a generated AES key stored in `flutter_secure_storage`. Auth tokens always use `flutter_secure_storage`.

**Eviction policy.** Set Redis eviction to `allkeys-lru` on both pilot (C0) and production (C1) instances. At current data volumes (pilot: ~8MB cached; production: ~220MB cached), eviction pressure is negligible — but the policy ensures the hottest data survives if it occurs.

### Never-cache list (hard prohibitions)

These four categories must never appear in a Redis cache entry or a Hive persistence entry, regardless of service or endpoint:

| Category | Specific fields | Reason |
| --- | --- | --- |
| OTP state | OTP code, verification result | Must be consumed on first successful verify and deleted immediately from Redis. Caching "verified" would allow replay. |
| Live billing totals | `currentArrears`, outstanding balance, any balance field that changes on payment receipt | Financial accuracy — changes on payment receipt; serving stale balance is a billing error. |
| Objection submission status | `ObjectionStatus` current value | User is watching it change. Push notification drives a live re-fetch; a cached status would show the wrong state after a transition. |
| POPIA-sensitive fields | `phoneNumber`, `email`, `idNumber`, `name` (User model); `rawPayload` on MunicipalityResponse (may contain PII from CRM) | Must not be stored in Redis (second vulnerable copy) or in unencrypted Hive (persists after logout). |

### Per-service cache policy

#### auth-service

| Layer | Policy | Detail |
| --- | --- | --- |
| Server Redis | No cache | JWT validation is a CPU operation (signature verify against the secret). No DB read per request. Adding Redis would add a network hop with no benefit. |
| Client Flutter | `flutter_secure_storage` only | Access token and refresh token stored in `flutter_secure_storage`. Never in Hive. Cleared on logout and on 401 response from any endpoint. |

#### otp-service

| Layer | Policy | Detail |
| --- | --- | --- |
| Server Redis | Primary store, not a cache | `SET otp:{userId}:{purpose} {hashedCode} EX 600` — Redis is authoritative. PostgreSQL OTPAttempt stores the audit trail only. Deleted from Redis on first successful verify (never left to expire naturally after a successful login). |
| Client Flutter | No persistence | OTP codes are entered from the user's SMS inbox. No client-side storage. |

Never-cache rule applies: once an OTP is verified, delete the Redis key immediately. Do not cache the verification result.

#### property-service

| Layer | Policy | Detail |
| --- | --- | --- |
| Server Redis | Cache property details | Key: `property:{propertyId}`. TTL: 24h. Property data changes only on valuation roll updates (~annually) or ownership transfers. At 98% read ratio (envelope.md), this is the highest-value cache in the system alongside bill-service. |
| Server Redis | Cache search results | Key: `property:search:{sha256(queryString)}`. TTL: 5min. Search results are less stable (new properties can be linked). Short TTL is correct. |
| Server Redis | Invalidation | On bulk municipality data refresh (future webhook): flush all `property:*` keys. At pilot scale, a manual `DEL property:*` on data import is acceptable. |
| Client Flutter | Property IDs in Hive | Store `[{ propertyId, erfNumber, serviceType }]` — no address, no owner name. TTL: 24h. Used to populate the Linked Properties screen without a round trip. Invalidate on `POST /property/link` or `DELETE /account/properties/:id` response. |
| Client Flutter | Address and owner name | Fetch live from `GET /property/:id` on Property Details Confirmation screen. Never in Hive (PII). Display only; cleared when screen is popped. |

#### account-service

| Layer | Policy | Detail |
| --- | --- | --- |
| Server Redis | Notification preferences | Key: `prefs:{userId}`. TTL: 1h. Boolean flags only — no PII. Invalidate on `PUT /account/preferences` (write-through: update DB first, then delete cache key). |
| Server Redis | Linked property ID list | Key: `account:properties:{userId}`. TTL: 1h. Stores `[propertyId, ...]` — no PII. Invalidate on `POST /property/link` or `DELETE /account/properties/:id`. |
| Server Redis | User profile | No cache. `phoneNumber`, `email`, `name` are PII (never-cache rule). Profile is read infrequently (only on Profile Settings screen open) — DB latency is acceptable. |
| Client Flutter | Notification preferences | Standard Hive (non-PII boolean flags). No TTL — valid until the user changes them. Cleared on logout. |
| Client Flutter | Linked property IDs | Hive. TTL: 24h. Same non-PII data as server cache. |
| Client Flutter | Profile (name, email, phone) | No Hive. Fetched live on Profile Settings screen open. Never persisted between launches. |

#### bill-service

| Layer | Policy | Detail |
| --- | --- | --- |
| Server Redis | Bill list | Key: `bill:list:{accountId}`. TTL: 6h. The list changes only when a new bill is added (once per month per account during the billing run). Invalidate on billing-run completion event (future webhook from billing system). |
| Server Redis | Bill line items | Key: `bill:lines:{billId}`. TTL: 24h. Line items are immutable after issue — no invalidation event exists; TTL is the only mechanism. |
| Server Redis | Home Dashboard summary | Key: `bill:dashboard:{userId}`. TTL: 1h. Summary totals used on the Home Dashboard screen. Invalidate on new bill event. |
| Server Redis | AI-generated expected amount | Key: `bill:ai:{billId}`. TTL: 1h. Short TTL because the `isStale` flag on AIAmountCalculation must be checked on every serve. If `isStale = true`, delete cache key and trigger recalculation. |
| Server Redis | Current arrears / outstanding balance | No cache. Live billing total (never-cache rule). Always fetched from PostgreSQL. |
| Client Flutter | Bill list and line items | Hive. TTL: 6h. Invalidate on `notification.new_bill` push receipt. Pre-populated when the user opens Bills List; available offline. |
| Client Flutter | Home Dashboard summary | Hive. TTL: 1h. The first thing shown on app open — cache allows instant display while background refresh runs. |
| Client Flutter | Arrears / outstanding balance | No Hive. Live fetch only. If offline, show "balance unavailable" — never show a stale financial total. |

#### objection-service

| Layer | Policy | Detail |
| --- | --- | --- |
| Server Redis | No cache | Write-heavy (40% writes, envelope.md). Every objection is in a distinct mutable state (draft → submitted → reference issued). Caching any part of this flow risks serving a stale draft after a network interruption. PostgreSQL is the authoritative state machine; always read from it. |
| Client Flutter | Objection draft | Hive. TTL: 7 days. Stores `{ draftId, disputeCategory, selectedChargeIds, stepIndex, notes }` — no PII, no financial amounts. Allows the user to resume a draft after app restart. Cleared on successful `POST /objections/:id/submit` response. If older than 7 days with no activity, display a "draft expired" prompt and clear. |
| Client Flutter | Evidence file paths | Hive alongside the draft. Store Blob Storage reference URLs returned by `POST /objections/:id/evidence`. Not the file content — just the URL. Cleared with the draft. |
| Client Flutter | Submission status | No Hive. Never-cache rule (user is watching it change). The reference number is displayed on the Submission Successful screen only; not persisted in Hive. Re-fetch from status-service if needed. |

#### notification-service

| Layer | Policy | Detail |
| --- | --- | --- |
| Server Redis | No cache | 70% write ratio during billing run (envelope.md). Paginated inbox view (`GET /notification`) uses an indexed `(user_id, created_at DESC)` PostgreSQL query against the 90-day rolling table. The index from plan/06-data-model is the latency lever, not caching. Cache invalidation across paginated pages on every new notification arrival would cost more than the DB query it saves. |
| Client Flutter | Notification inbox (page 1) | Hive. TTL: 1h. Stores the 20 most recent notifications for offline viewing. Invalidate immediately on any push notification receipt (FCM/APNs handler sets a `notificationsStale` flag in Hive; the next screen open re-fetches and refreshes). |

#### status-service

| Layer | Policy | Detail |
| --- | --- | --- |
| Server Redis | Current objection status | No cache. Never-cache rule (submission status — user is watching it change). Push notification arrives → Flutter re-fetches `GET /objections/:ref/status` live. Serving a cached pre-transition status after the push is worse than a DB read. |
| Server Redis | Objection history list | Key: `status:history:{userId}`. TTL: 5min. List of all past objections with summary status — changes infrequently (only when an objection resolves). Short TTL is the correct approach; do not invalidate on every status change (too frequent). |
| Client Flutter | Current objection status | No Hive persistence. On the Track Objection Status screen: fetch live on every `initState`. While screen is in foreground: poll every 30 seconds (complements push notifications for users who have disabled push). Cached in-memory for the current session only (standard Flutter state). |
| Client Flutter | Objection history list | Hive. TTL: 5min. Same short TTL as server cache. Cleared on any `notification.objection_status_change` push receipt. |

#### queue-consumer

| Layer | Policy | Detail |
| --- | --- | --- |
| Server Redis | No cache | Background worker only — no HTTP endpoints, no Flutter screens (service-map.md). Reads from BullMQ (which uses Redis as its own queue store, separate from the read-through cache). Writes results to PostgreSQL via notification-service and otp-service. No cacheable response surface exists. |
| Client Flutter | No client surface | Queue-consumer has no Flutter counterpart. |

### Redis memory sizing check

At production scale (25,000 registered users, 90,000 accounts, 1,080,000 bills):

| Cache key type | Estimated count | Avg payload | Total |
| --- | --- | --- | --- |
| `property:{propertyId}` | 30,000 | ~500 B | ~15 MB |
| `property:search:*` | ~500 active | ~200 B | ~0.1 MB |
| `prefs:{userId}` | 25,000 | ~100 B | ~2.5 MB |
| `account:properties:{userId}` | 25,000 | ~200 B | ~5 MB |
| `bill:list:{accountId}` | 90,000 | ~300 B | ~27 MB |
| `bill:lines:{billId}` | ~90,000 hot bills | ~1 KB | ~90 MB |
| `bill:dashboard:{userId}` | 25,000 | ~300 B | ~7.5 MB |
| `bill:ai:{billId}` | ~5,000 active | ~500 B | ~2.5 MB |
| `status:history:{userId}` | 25,000 | ~400 B | ~10 MB |
| **Total** | | | **~160 MB** |

Production Redis C1 capacity: 1 GB. Headroom: 840 MB. No memory pressure at 12-month production scale. The `allkeys-lru` eviction policy is a safety net, not an active mechanism at this volume.

Pilot Redis C0 capacity: 250 MB. Scaled down ~10×: ~16 MB. Well within 250 MB.

---

## CDN Decision

**No CDN. Not at pilot. Not at production. Revisit only if a Flutter Web channel is added.**

### Reasoning

**Municipal branding is not served via HTTP.** Logos, fonts, color palette, and all UI assets are compiled into the Flutter APK/IPA at build time. They are distributed via Google Play and the Apple App Store — which are themselves global CDNs. There is no HTTP origin to put a CDN in front of.

**Evidence template PDFs are too small and too infrequent to justify a CDN.** At production scale, 2,500 objections per year means roughly 2,500 template downloads per year — seven per day on average. Azure Blob Storage in South Africa North serves seven requests per day without measurable latency or cost impact. The CDN would handle the same load at higher infrastructure complexity and no user-visible benefit.

**The origin is already co-located with the users.** Emfuleni ratepayers are in the Vaal Triangle. Azure's South Africa North region is in Johannesburg — the nearest Azure region. The round-trip from Emfuleni to SA North Blob Storage is already 5–15 ms. Azure CDN's nearest SA edge node is also in Johannesburg. A CDN would route through the same physical location as the origin, yielding zero latency reduction.

**Downloadable content is either dynamic or absent.** Property PDF reports (`GET /property/:id/pdf`) are generated per-account — not static, not cacheable at a CDN edge. No other large downloadable content is defined in service-map.md. If a tariff schedule PDF were added in future, it would be a single file downloaded by a small fraction of users — Blob Storage public URL is the correct delivery mechanism.

**A CDN is not a performance lever for this architecture.** The P95 latency targets in this plan are determined by the Node.js API tier and the Azure SQL read path. CDN addresses the static-asset delivery problem, which is not the bottleneck here.

### What would change this decision

Add Azure CDN Standard (Microsoft tier, ~$0.081/GB egress SA North) if any of the following becomes true:

| Trigger | Why it changes the decision |
| --- | --- |
| Flutter Web is added as a second client channel | JS/CSS/WASM bundles (5–20 MB per user on first load) served to browsers globally — CDN is essential |
| A public-facing tariff info page is added (static HTML) | Browser clients, globally accessible, no auth — CDN is the correct origin shield |
| Evidence template PDFs exceed 10 MB each AND download volume > 500/day | At that volume, Blob Storage egress costs and latency become relevant |

Until one of these triggers fires, the CDN task is closed and no Azure CDN resource is provisioned.

---

## Hosting Decision

**Azure App Service for Containers. Pilot: one B1 plan. Production: three P1v3 plans.**

This is a confirmation, not a fresh choice. envelope.md already priced App Service in the cost model. This section documents the rejection of ACI and AKS, confirms the model, and derives the hard constraints that plan/08 must respect.

### Why not ACI

ACI's billing model (per second, containers stop when idle) is its main selling point and its main problem here. Three specific incompatibilities:

**BullMQ requires a persistent Redis connection.** queue-consumer runs a blocking `BLPOP`-style subscriber against Redis. If ACI stops the container between jobs, the subscriber drops and jobs queue silently. App Service's "Always On" setting (`alwaysOn: true`) keeps the process alive between requests.

**No built-in load balancing for multi-service apps.** Seven ACI containers require a separate Azure Load Balancer or Application Gateway to route traffic between services. App Service gives each service its own stable HTTPS hostname (`<service>.azurewebsites.net`) with TLS termination included, plus VNet integration for internal service-to-service calls — all without additional infrastructure.

**No deployment slots.** ACI offers no staging/production swap. App Service deployment slots let you deploy to staging, run smoke tests, then swap — zero-downtime deploy. This matters on pilot: the team is small, deploys will be frequent, and a failed deploy during objection submission hours is a deadline-day risk.

ACI becomes relevant only if the services migrate to an event-driven, stateless architecture with no persistent queue consumer. That is not the current design.

### Why not AKS

AKS is the right answer when the team has Kubernetes expertise and the workload demands pod-level autoscale, multi-replica deployments, or custom ingress routing. None of those conditions exist at pilot.

At 500 peak concurrent sessions (envelope.md), the load on a B1 plan is: ~15–25 concurrent DB queries (Basic 5 DTU headroom is 30 max workers), Redis absorbing ~97% of property/bill reads, and Node.js event-loop serving the rest. A single B1 instance handles this. There is no scaling problem for AKS to solve.

AKS minimum viable cluster: one System node pool (Standard_B2s, ~$30–40/month) plus a User node pool for workloads (~$60–80/month). That doubles the pilot compute cost ($34/month → $100+/month) before any workload runs. The overhead is not justified.

**Revisit AKS at the production → scale-out transition** (roughly when registered users exceed 50,000 or the team grows to include a dedicated platform engineer). Until then, App Service autoscale (horizontal instance addition per plan) handles burst without cluster ops.

### Why App Service for Containers

App Service for Containers is App Service's container-native mode: instead of deploying source code, you deploy a Docker image from Azure Container Registry (ACR). The App Service plan (B1, P1v3) is unchanged — the billing, scaling, and ops surface are identical to regular App Service, but each app runs a container image pulled from ACR.

Four reasons this wins for EasyRates pilot:

1. **Envelope.md already chose the tier.** App Service B1 (pilot, $13/month SA North $14.95) and P1v3 × 3 (production) are in the confirmed cost model. Switching to ACI or AKS would invalidate the cost model without a corresponding benefit.

2. **No cluster ops.** The pilot team has no dedicated SRE. App Service removes: OS patching, node pool sizing, ingress controller management, cert-manager, RBAC configuration, and etcd backups. Deploy surface is: push image to ACR, `az webapp config container set`. That is the entire ops footprint.

3. **Plan/08 is building Podman Compose for local dev.** The Docker images built for local development are the same images pushed to ACR and run in App Service. Dev-to-prod parity is exact: same image, same environment variables (injected via App Service Application Settings instead of env_file), different host. No translation layer.

4. **Always On keeps queue-consumer alive.** `alwaysOn: true` is a standard App Service setting available on B1 and above. It ensures the BullMQ subscriber process is never killed for inactivity.

### Constraints for plan/08

These constraints are derived from the hosting decision and must be respected in plan/08's ASSIGN task. Plan/08 may not override them without raising a change here first.

| Constraint | Value | Reason |
| --- | --- | --- |
| Container unit | One Docker image per service module | App Service for Containers runs single-container apps. No sidecar pattern (multi-container Docker Compose on App Service is deprecated). |
| Pilot resource ceiling | 1 vCPU / 1.75 GB RAM total across all 7 services | One B1 plan shared by all 7 apps (envelope.md). Plan/08 ASSIGN task must ensure per-service limits sum to ≤ this ceiling. |
| Production resource ceiling | 2 vCPU / 8 GB RAM per plan × 3 plans | Three P1v3 plans. Service grouping (envelope.md): [auth, otp, property] · [account, bill] · [objection, notification]. queue-consumer attaches to the objection plan. |
| Always On | Required for queue-consumer | Prevents BullMQ Redis subscriber from being killed between jobs. Applied at App Service app level, not plan level. |
| Image registry | Azure Container Registry (ACR) Basic (~$5/month) | Private registry; no Docker Hub dependency; ACR integrates natively with App Service pull credentials. |
| Health check endpoint | `GET /health → 200` on every service | App Service health check pings this URL; failure triggers container restart. plan/08 HEALTHCHECKS task must document this endpoint before the compose file is useful. |
| Environment variables | App Service Application Settings (production) / `.env` file (local dev) | No secrets in the Docker image. App Service injects env vars at runtime identically to `--env-file` in Podman. |
| Connectivity to Azure SQL and Redis | Public endpoint + firewall rules (pilot) / VNet integration (production) | Pilot: App Service outbound IPs added to Azure SQL firewall allowlist and Redis access policy. Production: Regional VNet Integration required to keep traffic off the public internet. |

### Hosting decision summary

| Dimension | Pilot | Production |
| --- | --- | --- |
| Model | Azure App Service for Containers | Azure App Service for Containers |
| Plan | B1 (1 vCPU, 1.75 GB RAM, 1 instance) | P1v3 × 3 plans (2 vCPU, 8 GB RAM each, autoscale to 2 instances per plan during spike) |
| Services per plan | All 7 Node.js services + queue-consumer | [auth, otp, property] · [account, bill] · [objection, notification, queue-consumer] |
| Image registry | ACR Basic | ACR Basic → Standard if > 10 repos |
| Scale trigger | Manual (no autoscale at pilot load) | CPU > 70% sustained for 5 min → add 1 instance per plan |
| Ops surface | `az webapp config container set` per deploy | GitHub Actions → ACR build → App Service rolling deploy |

---

## NFR Alert Manifest

All alerts target **production** thresholds. Pilot uses the same rules with thresholds
swapped per the P95 and availability target tables above — annotated inline.

Eleven alerts cover three tiers:

- **Target alerts (7)** — fire when an NFR target is already being violated.
- **Precursor alerts (3)** — fire when infrastructure is degrading toward a violation.
- **Data accuracy alert (1)** — the critical NFR; requires custom Application Insights
  telemetry emitted by bill-service (spec below).

Signal types used:

- **Scheduled Query Rule (SQR)** — KQL against Log Analytics workspace connected to
  Application Insights. Use for latency, availability, data accuracy.
- **Metric Alert** — native Azure Monitor metrics on Azure SQL and Redis resources.
  Use for DTU and Redis load (lower latency, no Log Analytics ingestion lag).

### Master alert table

| # | Alert name | Tier | NFR target | Threshold (prod) | Threshold (pilot) | Sev | Frequency | Window | Action group |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `latency-otp-p95` | Target | OTP send P95 | > 200 ms | > 400 ms | 2 | 1 min | 5 min | `ag-warning` |
| 2 | `latency-property-p95` | Target | Property lookup P95 | > 100 ms | > 300 ms | 2 | 1 min | 5 min | `ag-warning` |
| 3 | `latency-bill-p95` | Target | Bill fetch P95 | > 150 ms | > 500 ms | 2 | 1 min | 5 min | `ag-warning` |
| 4 | `latency-objection-p95` | Target | Objection submit P95 | > 300 ms | > 400 ms | 1 | 1 min | 5 min | `ag-deadline` |
| 5 | `latency-notification-p95` | Target | Notification list P95 | > 150 ms | > 400 ms | 2 | 1 min | 5 min | `ag-warning` |
| 6 | `availability-outage` | Target | Availability | = 0% for 10 min | = 0% for 15 min | 0 | 1 min | 10 min | `ag-critical` |
| 7 | `availability-sla-breach` | Target | 30-day SLA | < 99.9% | < 99.0% | 1 | 1 h | 30 d | `ag-warning` |
| 8 | `data-accuracy-estimate-streak` | Target | Data accuracy | any account ≥ 2 consecutive estimates | any pilot account ≥ 2 | 1 | 1 h | 1 h | `ag-billing` |
| 9 | `infra-dtu-saturation` | Precursor | SQL capacity headroom | > 80% DTU for 15 min | > 80% DTU for 15 min | 2 | 5 min | 15 min | `ag-warning` |
| 10 | `infra-redis-load` | Precursor | Redis capacity headroom | > 80% serverLoad for 10 min | > 80% serverLoad for 10 min | 2 | 5 min | 10 min | `ag-warning` |
| 11 | `infra-connection-pool-errors` | Precursor | Prisma pool (28/30 limit) | > 5 pool timeout errors in 5 min | > 5 pool timeout errors in 5 min | 1 | 1 min | 5 min | `ag-deadline` |

**Azure Monitor severity mapping:** 0 = Critical, 1 = Error, 2 = Warning.

**Action groups** (define once in Azure Monitor, reference by name):

| Name | Receivers | When used |
| --- | --- | --- |
| `ag-critical` | PagerDuty on-call + Teams `#ops-alerts` | Sev 0 — system down |
| `ag-deadline` | PagerDuty on-call + Teams `#ops-alerts` + email ops-team | Sev 1 — objection deadline at risk |
| `ag-billing` | Email ops-team + SMS to billing lead | Sev 1 — data accuracy NFR |
| `ag-warning` | Teams `#ops-alerts` only | Sev 2 — degraded, not down |

### Alert 1–5: P95 latency (Scheduled Query Rules)

Wire the `applicationinsights` npm SDK in every Node.js service at startup. The SDK
auto-populates the `requests` table with `name`, `duration` (ms), `success`, and `url`.

All five rules share the same structure — only `name` and `where p95_ms >` differ.

```kusto
// Alert 1 — latency-otp-p95
// Production threshold: 200 ms. Pilot: change to 400.
requests
| where timestamp > ago(5m)
| where name == "POST /api/v1/otp/send"
| summarize p95_ms = percentile(duration, 95) by bin(timestamp, 1m)
| where p95_ms > 200

// Alert 2 — latency-property-p95
// Production threshold: 100 ms. Pilot: 300.
requests
| where timestamp > ago(5m)
| where name startswith "GET /api/v1/property"
| summarize p95_ms = percentile(duration, 95) by bin(timestamp, 1m)
| where p95_ms > 100

// Alert 3 — latency-bill-p95
// Production threshold: 150 ms. Pilot: 500.
requests
| where timestamp > ago(5m)
| where name startswith "GET /api/v1/bill"
| summarize p95_ms = percentile(duration, 95) by bin(timestamp, 1m)
| where p95_ms > 150

// Alert 4 — latency-objection-p95  [Sev 1 — deadline risk]
// Production threshold: 300 ms. Pilot: 400.
// A slow 202 on objection submit drives retries → duplicate submissions under deadline pressure.
requests
| where timestamp > ago(5m)
| where name == "POST /api/v1/objection"
| summarize p95_ms = percentile(duration, 95) by bin(timestamp, 1m)
| where p95_ms > 300

// Alert 5 — latency-notification-p95
// Production threshold: 150 ms. Pilot: 400.
requests
| where timestamp > ago(5m)
| where name startswith "GET /api/v1/notification"
| summarize p95_ms = percentile(duration, 95) by bin(timestamp, 1m)
| where p95_ms > 150
```

**Rule parameters (apply to all 5):**

| Parameter | Value |
| --- | --- |
| Evaluation frequency | 1 minute |
| Lookback window | 5 minutes |
| Alert logic | Result count > 0 (any row returned = threshold exceeded) |
| Auto-resolve | Yes — resolves when next evaluation returns 0 rows |

### Alert 6: Immediate outage (Scheduled Query Rule)

Application Insights URL ping test must be configured first (one test per entry-point
service: auth, otp, bill). See Availability Targets § Measurement.

```kusto
// Alert 6 — availability-outage  [Sev 0 — system down]
// Fires when ALL ping tests fail simultaneously for 10 minutes.
// Two consecutive failures from ≥ 2 locations = outage start.
availabilityResults
| where timestamp > ago(10m)
| summarize
    total   = count(),
    passed  = countif(success == 1)
| extend success_rate = todouble(passed) / todouble(total)
| where success_rate == 0
```

| Parameter | Production | Pilot |
| --- | --- | --- |
| Evaluation frequency | 1 minute | 1 minute |
| Lookback window | 10 minutes | 15 minutes |
| Alert logic | Result count > 0 | Result count > 0 |
| Action group | `ag-critical` | `ag-critical` |
| Auto-resolve | Yes | Yes |

### Alert 7: Rolling 30-day SLA breach (Scheduled Query Rule)

```kusto
// Alert 7 — availability-sla-breach  [Sev 1]
// Production: fires when 30-day rolling availability drops below 99.9%.
// Pilot: change threshold to 99.0.
availabilityResults
| where timestamp > ago(30d)
| summarize availability_pct = 100.0 * avg(todouble(success))
| where availability_pct < 99.9
```

| Parameter | Value |
| --- | --- |
| Evaluation frequency | 1 hour |
| Lookback window | 30 days |
| Alert logic | Result count > 0 |
| Action group | `ag-warning` |
| On fire | Block all non-emergency deployments for remainder of month. Record SLA credit claim start time for Azure support ticket. |

### Alert 8: Data accuracy — consecutive estimate streak (Scheduled Query Rule)

**This alert requires custom telemetry to be emitted by bill-service.**

bill-service must call `telemetryClient.trackEvent()` whenever it loads billing data
for an account and detects two or more consecutive estimated reads:

```typescript
// In bill-service — call when loading bills for an account
function checkEstimateStreak(bills: Bill[], accountId: string): void {
  // Walk bills newest-first; count the head run of 'E' (Estimated) reads
  let streakCount = 0
  for (const bill of [...bills].sort((a, b) =>
    b.billingPeriodStart.localeCompare(a.billingPeriodStart)
  )) {
    if (bill.readType === 'E') streakCount++
    else break
  }
  if (streakCount >= 2) {
    telemetryClient.trackEvent({
      name: 'EstimatedReadStreak',
      properties: {
        accountId,
        consecutiveCount: String(streakCount),
        latestBillId: bills[0].id,
        billingPeriodStart: bills[0].billingPeriodStart,
      },
    })
  }
}
```

Call `checkEstimateStreak` inside the `GET /bill/account/:accountId` handler after
fetching the bill list. The event fires at most once per bill-list request where a
streak exists — it does not create alert noise on non-streaking accounts.

```kusto
// Alert 8 — data-accuracy-estimate-streak  [Sev 1]
// Fires when any account has ≥ 2 consecutive estimated reads in the last hour.
customEvents
| where timestamp > ago(1h)
| where name == 'EstimatedReadStreak'
| extend consecutiveCount = toint(customDimensions.consecutiveCount)
| where consecutiveCount >= 2
| summarize
    accountsAtRisk = dcount(tostring(customDimensions.accountId)),
    maxStreak      = max(consecutiveCount)
| where accountsAtRisk > 0
```

| Parameter | Value |
| --- | --- |
| Evaluation frequency | 1 hour |
| Lookback window | 1 hour |
| Alert logic | Result count > 0 |
| Action group | `ag-billing` |
| On fire | Ops manually verifies the flagged account against physical statement. At pilot scale (3 test accounts), this is a phone call. At production scale, this is an automated verification queue. |

**Why this is Sev 1 and not Sev 2.** An estimated-read streak that reaches cycle 2 is
the last warning before a catch-up spike bill. If it is not caught here, the ratepayer
will receive a bill that is potentially hundreds of rands higher than expected, with no
advance notice — exactly the scenario EasyRates was built to prevent. Latency at Sev 2
means users are slowed. This at Sev 1 means a user is about to be financially harmed.

### Alerts 9–11: Infrastructure precursor alerts (Metric Alerts)

These are native Azure Monitor Metric Alerts, not KQL queries. They are cheaper to
evaluate (no Log Analytics ingestion lag) and are appropriate for continuous numeric
metrics on infrastructure resources.

**Alert 9 — `infra-dtu-saturation`**

Sustained DTU > 80% means the SQL tier is approaching its throughput ceiling. At 100%,
new queries queue — which shows up as latency spikes 2–5 minutes later. Alert at 80%
to create intervention time before the latency alert fires.

```text
Resource:       Azure SQL database (easyrates-pilot or easyrates-prod)
Signal:         dtu_consumption_percent
Condition:      Average > 80
Aggregation:    Average over 15 minutes
Evaluation:     Every 5 minutes
Severity:       2 (Warning)
Action group:   ag-warning
Resolution:     If sustained > 80% for 30 min → escalate to S3 (100 DTU). Online
                scaling; no data migration.
```

**Alert 10 — `infra-redis-load`**

Redis `server_load` > 80% means CPU on the Redis node is saturating. At saturation,
get/set operations start queuing. Cache hit path becomes slower than the alert
threshold on the latency rules — so this fires before the latency alert does.

```text
Resource:       Azure Cache for Redis (easyrates-pilot or easyrates-prod)
Signal:         server_load (percentage)
Condition:      Average > 80
Aggregation:    Average over 10 minutes
Evaluation:     Every 5 minutes
Severity:       2 (Warning)
Action group:   ag-warning
Resolution:     If sustained → scale from C0 to C1 (pilot) or C1 to C2 (production).
                Note: Azure Cache for Redis Basic/Standard/Premium retirement — verify
                Azure Managed Redis availability in SA North before scaling beyond C1.
```

**Alert 11 — `infra-connection-pool-errors` (Scheduled Query Rule)**

Prisma is configured at `connection_limit = 4` per service (7 × 4 = 28 < Basic 30-worker
ceiling). If any service exceeds its pool limit, Prisma queues new queries and eventually
throws `PrismaClientKnownRequestError` with `"Timed out fetching a new connection from
the connection pool"`. These are logged as exceptions in Application Insights.

```kusto
// Alert 11 — infra-connection-pool-errors  [Sev 1]
// Fires when pool timeout errors exceed 5 in a 5-minute window.
// Fewer than 5 may be transient; ≥ 5 means the pool is consistently exhausted.
exceptions
| where timestamp > ago(5m)
| where type contains "PrismaClientKnownRequestError"
     or outerMessage contains "connection pool"
     or outerMessage contains "Timed out fetching"
| summarize errorCount = count() by cloud_RoleName
| where errorCount > 5
```

| Parameter | Value |
| --- | --- |
| Evaluation frequency | 1 minute |
| Lookback window | 5 minutes |
| Alert logic | Result count > 0 |
| Action group | `ag-deadline` (Sev 1 — pool exhaustion can cascade to latency + 500 errors) |
| On fire | Check which `cloud_RoleName` is exhausting its pool. Immediate fix: `connection_limit` on that service may be too low, or that service has a query that holds connections open (long-running transaction, missing `await`). |

### Verification that all targets are covered

| NFR target | Alert | "We'll know when users complain" without it? |
| --- | --- | --- |
| OTP send P95 | `latency-otp-p95` (alert 1) | Yes — login failures would spike on the same requests table, but latency degradation below failure threshold would be invisible. |
| Property lookup P95 | `latency-property-p95` (alert 2) | Yes — caching means most users never notice; the uncached 2% would complain after a long wait. |
| Bill fetch P95 | `latency-bill-p95` (alert 3) | Yes — the most-visited screen. Users would complain, but not immediately. |
| Objection submit P95 | `latency-objection-p95` (alert 4) | Yes — and by then a deadline may have passed. This is the highest-stakes latency target. |
| Notification list P95 | `latency-notification-p95` (alert 5) | Yes — low-traffic screen; poor P95 here would take days to surface. |
| 99.9% availability | `availability-outage` + `availability-sla-breach` (alerts 6–7) | Yes — and if the system is down on deadline day, users cannot complain to fix it in time. |
| Data accuracy (critical NFR) | `data-accuracy-estimate-streak` (alert 8) | Yes — the entire pilot value proposition is detecting this. Without the alert, detection relies on the ratepayer receiving the spike bill and reporting it. That is the failure mode EasyRates was built to prevent. |
| SQL capacity | `infra-dtu-saturation` (alert 9) | Yes — saturation shows up as latency, which then shows up as user complaints ~5 min later. |
| Redis capacity | `infra-redis-load` (alert 10) | Yes — Redis saturation causes cache misses, which cause latency spikes, which eventually trigger user complaints. |
| Prisma connection pool | `infra-connection-pool-errors` (alert 11) | Yes — pool exhaustion causes 500 errors on the affected service. Users see error screens. |

No target relies on user complaints. Every row above has an alert that fires before or at the moment of violation.
