# EasyRates — Non-Functional Requirements

_Source of truth for all NFR decisions. Every quantitative target here was derived in
`easy_rates/system-design/plans/05-nfr.md` — refer there for full derivation, KQL
alert queries, and operating procedures. This document is the **reference** (scannable,
all decisions resolved); plan/05 is the **workbook** (reasoning, alternatives, edge cases)._

_Load anchor from `docs/envelope.md` (do not re-derive):_
_**Pilot peak: 500 concurrent sessions. Production peak: 5,000 concurrent sessions.**_
_Basis: 20% of registered users (pilot: 2,500; production: 25,000) in a 15-minute_
_WhatsApp-driven social spike. This figure governs every target below._

---

## Critical NFR — Data Accuracy

**The one NFR whose violation kills the pilot.**

| Dimension | Pilot "good enough" | Production required |
| --- | --- | --- |
| kL delta correctness | Correct to within ±1 kL per line item for 3 pilot test accounts, verified against physical statements and manual meter readings | Correct to within ±1 kL across all accounts; automated regression on every billing-run import |
| Materiality threshold | R50 discrepancy per cycle triggers a flag (pending Emfuleni disputes policy confirmation) | Same threshold, automated |
| Estimated-read detection | A/E flag parsed from billing data; consecutive-estimate counter increments per cycle | Same; alert fires at cycle 2 (before the catch-up spike bill, not after) |
| Ground truth | Physical statements + manual meter readings for pilot test accounts | Billing system export; municipality confirms correct kL figure per disputed account |

**Monitoring signal.** The consecutive-estimate counter is the leading indicator — it fires
at cycle 2, before the ratepayer receives the catch-up bill. Any counter reaching 2 for
a pilot account triggers a manual verification call with the 3 pilot contacts.
Availability and latency failures are recoverable. A billing amount that is wrong and
undetected destroys the municipality's trust in the system and ends the pilot.

---

## P95 Latency Targets

_Derived from the Azure tier capacity working backwards from peak concurrent sessions.
Tiers: Pilot = Basic 5 DTU + App Service B1 × 1 + Redis C0.
Production = S2 50 DTU + P1v3 × 3 plans + Redis C1._
_These targets are the single source of truth. plan/08 copies them verbatim._

| Endpoint | Pilot P95 | Production P95 | Tier that delivers it |
| --- | --- | --- | --- |
| OTP send — `POST /otp/send` → 202 | **400 ms** | **200 ms** | Pilot: Basic + B1. Prod: S2 + P1v3 |
| Property lookup — `GET /property/*` → 200 | **300 ms** | **100 ms** | Pilot: Basic + B1 + C0. Prod: S2 + P1v3 + C1 |
| Bill fetch — `GET /bill/*` → 200 | **500 ms** | **150 ms** | Pilot: Basic + B1 + C0. Prod: S2 + P1v3 + C1 |
| Objection submit — `POST /objection` → 202 | **400 ms** | **300 ms** | Pilot: Basic + B1. Prod: S2 + P1v3 |
| Notification list — `GET /notification` → 200 | **400 ms** | **150 ms** | Pilot: Basic + B1. Prod: S2 + P1v3 |

**Key derivation facts (not targets — for context):**

- OTP send and objection submit are async 202 responses. Twilio and Blob Storage are off the critical path.
- Property and bill endpoints are 98%/97% read (envelope.md). Redis absorbs almost all traffic; P95 is set to cover the spike warmup window before cache warms.
- Notification list is not cached (70% write ratio during billing run). PostgreSQL index on `(user_id, created_at DESC)` is the only latency lever.
- Pilot Prisma `connection_limit = 4` per service (7 × 4 = 28 < Basic 30-worker ceiling). This is a hard requirement, not a recommendation.

**Monitoring.** Application Insights `requests` table (wire `applicationinsights` npm SDK at startup). One Scheduled Query Alert per endpoint, 5-minute window, 1-minute frequency. Full KQL queries in plan/05-nfr.md § Measurement.

Supporting metrics (dashboard, not alerts):

- `requests/duration` P95 per operation name — 24h rolling
- Azure SQL `dtu_consumption_percent` — alert at sustained > 80%
- Redis `serverLoad` — alert at sustained > 80%
- Redis cache miss ratio — spike above 10% is expected for first 2–3 minutes of a social spike, then recovers

---

## Availability Targets

| Phase | Target | Allowable downtime/month | Binding constraint |
| --- | --- | --- | --- |
| Pilot | **99%** | 7.2 hours | Azure composite SLA ~99.44% (Redis C0 has no contractual SLA). Single B1 instance — no redundancy. Pilot is not the primary dispute channel; civic offices remain open. |
| Production | **99.9%** | 43 minutes | Redis C1 Standard SLA = 99.9% — the binding constraint. App Service P1v3 and Azure SQL S2 both exceed this. |

**Azure SLA components:**

| Component | Pilot tier | Pilot SLA | Production tier | Production SLA |
| --- | --- | --- | --- | --- |
| App Service | B1 Basic | 99.95% | P1v3 Premium v3 | 99.95% |
| Azure SQL | Basic 5 DTU | 99.99% | S2 Standard 50 DTU | 99.99% |
| Redis | C0 Basic | No SLA | C1 Standard | 99.9% |
| **Composite** | — | **~99.44%** | — | **~99.84%** |

**Deadline-day risk.** The SA Municipal Systems Act (s.95) and Municipal Property Rates Act
impose hard deadlines on billing disputes and valuation roll objections (30 days from
statement/notice). Downtime on the last afternoon of an objection window is a rights
problem — the ratepayer loses legal standing. This asymmetry drives the operating
procedure below, not just the headline percentage.

**Maintenance blackout.** Final 3 days of each billing period: no deployments, no schema
changes, no Redis flushes. Production: pre-scale to 2 instances/plan at T−48h before
deadline close. Do not rely on autoscale to trigger this — pre-scale manually.

**Monitoring:**

- Application Insights URL ping test: `GET /health → 200` on auth, otp, and bill services. Cadence: every 5 minutes. Locations: South Africa North (primary) + West Europe (canary). Outage = 2 consecutive failures from ≥ 2 locations.
- Immediate outage alert: `availabilityResults` where success_rate = 0 in last 10 minutes → PagerDuty / Teams immediate page.
- Rolling SLA alert: 30-day availability < 99.9% (production) / < 99.0% (pilot) → block non-emergency deployments for remainder of month.
- Full KQL queries in plan/05-nfr.md § Measurement.

---

## Caching Strategy

### Never-cache list — hard prohibitions at all layers

| Category | Specific fields | Reason |
| --- | --- | --- |
| OTP state | OTP code, verification result | Consumed and deleted from Redis on first successful verify. Caching "verified" allows replay. |
| Live billing totals | `currentArrears`, outstanding balance | Changes on payment receipt. Stale balance = billing error. |
| Objection submission status | `ObjectionStatus` current value | User is watching it change. Push notification drives a live re-fetch. |
| POPIA-sensitive fields | `phoneNumber`, `email`, `idNumber`, `name`; `rawPayload` on MunicipalityResponse | Not stored in Redis or unencrypted Hive. Auth tokens in `flutter_secure_storage` only. |

### Cache policy per service

_Redis eviction policy: `allkeys-lru` on both C0 (pilot) and C1 (production)._
_All Redis keys are user- or entity-scoped to prevent cross-user leakage._
_Hive = unencrypted. Only non-PII fields stored in standard Hive._

| Service | Server Redis | Redis key | TTL | Client Flutter | Invalidation trigger |
| --- | --- | --- | --- | --- | --- |
| **auth** | No cache | — | — | Tokens: `flutter_secure_storage` only (never Hive) | Logout / 401 response |
| **otp** | Primary store (not a cache) | `otp:{userId}:{purpose}` | 600 s | No persistence | Deleted on successful verify |
| **property** | Property details | `property:{propertyId}` | 24 h | Non-PII IDs `{propertyId, erfNumber}` in Hive | Municipality data refresh; manual flush on import |
| **property** | Search results | `property:search:{sha256(query)}` | 5 min | — | — |
| **account** | Notification preferences | `prefs:{userId}` | 1 h | Preferences in Hive (boolean flags, non-PII) | `PUT /account/preferences` |
| **account** | Linked property IDs | `account:properties:{userId}` | 1 h | Property IDs in Hive, TTL 24 h | `POST /property/link` or DELETE response |
| **account** | User profile (name, email, phone) | **No cache** — PII | — | No Hive — live fetch on Profile screen | — |
| **bill** | Bill list | `bill:list:{accountId}` | 6 h | Bill list + line items in Hive, TTL 6 h | `notification.new_bill` push receipt |
| **bill** | Bill line items | `bill:lines:{billId}` | 24 h | (shared with bill list Hive entry) | Immutable after issue |
| **bill** | Home Dashboard summary | `bill:dashboard:{userId}` | 1 h | Dashboard in Hive, TTL 1 h | `notification.new_bill` push receipt |
| **bill** | AI-generated expected amount | `bill:ai:{billId}` | 1 h | No Hive | `isStale = true` on AIAmountCalculation |
| **bill** | Current arrears / balance | **No cache** — live financial total | — | No Hive — show "unavailable" if offline | — |
| **objection** | No cache | — | — | Draft `{category, chargeIds, stepIndex}` in Hive, TTL 7 d | Successful submission |
| **objection** | — | — | — | Evidence file URLs in Hive (not file content) | Cleared with draft |
| **objection** | Submission status | **No cache** — never | — | No Hive | — |
| **notification** | No cache (70% write ratio) | — | — | Inbox page 1 (20 items) in Hive, TTL 1 h | Any push notification receipt |
| **status** | Current objection status | **No cache** — never | — | No Hive — live fetch on `initState`; poll 30 s in foreground | — |
| **status** | Objection history list | `status:history:{userId}` | 5 min | History in Hive, TTL 5 min | `notification.objection_status_change` push |
| **queue-consumer** | No cache (no HTTP surface) | — | — | No client surface | — |

**Redis memory at production scale (~160 MB used / 1 GB C1 capacity):**
`bill:lines` hot bills = ~90 MB dominant. No eviction pressure at 12-month scale.
Pilot: ~16 MB / 250 MB C0 capacity.

---

## CDN Decision

**No CDN — not at pilot, not at production.**

| Asset type | Delivery mechanism | Reason no CDN needed |
| --- | --- | --- |
| Municipal branding (logos, fonts, colors) | Compiled into Flutter APK/IPA at build time | Not served via HTTP. Distributed via Google Play / App Store (which are CDNs). |
| Evidence template PDFs | Azure Blob Storage SA North direct URL | ~2,500 downloads/year at production (7/day). SA North Blob Storage is already in Johannesburg — same location as users. CDN edge node would be in the same location. |
| Property PDF reports | Node.js generated per request | Dynamic, per-account. Not cacheable at a CDN edge. |

**Revisit triggers (Azure CDN Standard, ~$0.081/GB egress SA North):**

- Flutter Web is added as a second client channel (JS/WASM bundles require CDN)
- Public-facing tariff info page is added (browser clients, no auth)
- Template PDFs exceed 10 MB each AND download volume exceeds 500/day

Until a trigger fires, no Azure CDN resource is provisioned.

---

## Hosting Decision

**Azure App Service for Containers. Pilot: 1 × B1 plan. Production: 3 × P1v3 plans.**

| Dimension | Pilot | Production |
| --- | --- | --- |
| Model | Azure App Service for Containers | Azure App Service for Containers |
| Plan | B1 — 1 vCPU, 1.75 GB RAM, 1 instance | P1v3 × 3 plans — 2 vCPU, 8 GB RAM each |
| Services per plan | All 7 Node.js services + queue-consumer share 1 plan | [auth, otp, property] · [account, bill] · [objection, notification, queue-consumer] |
| Image registry | ACR Basic (~$5/month) | ACR Basic → Standard if > 10 repos |
| Scale trigger | Manual — no autoscale needed at 500 concurrent | CPU > 70% sustained 5 min → add 1 instance per plan. Pre-scale to 2 instances/plan at T−48h before deadline. |
| Deploy surface | `az webapp config container set` | GitHub Actions → ACR build → App Service rolling deploy |
| Monthly cost (SA North) | ~$14.95 (B1) + ~$5 (ACR) | ~$427.80 (3 × P1v3) + ~$5 (ACR) |

**ACI rejected:** per-second billing model stops containers between jobs, which breaks
the BullMQ Redis subscriber in queue-consumer. No built-in load balancing across 7
services. No deployment slots (no zero-downtime swap).

**AKS rejected:** At 500 pilot concurrent sessions the workload does not need pod-level
autoscale or multi-replica orchestration. Minimum viable AKS cluster doubles the pilot
compute cost (~$100+/month vs $14.95) before a single workload runs. Revisit when
registered users exceed 50,000 or a dedicated platform engineer joins.

**Hard constraints for plan/08 (ASSIGN task):**

| Constraint | Value |
| --- | --- |
| Container unit | One Docker image per service. No sidecar containers. |
| Pilot resource ceiling | Sum of all 7 services ≤ 1 vCPU / 1.75 GB RAM |
| Production resource ceiling | Sum of services per plan ≤ 2 vCPU / 8 GB RAM |
| Always On | Required for queue-consumer (`alwaysOn: true`) |
| Image registry | ACR — no Docker Hub |
| Health check endpoint | `GET /health → 200` on every service |
| Env vars | App Service Application Settings (prod) / `.env` (local) — no secrets in image |
| DB/Redis connectivity | Pilot: public endpoint + IP firewall. Production: Regional VNet Integration. |

---

## Monitoring — Alert Manifest

_Full KQL and implementation notes in `plans/05-nfr.md` § NFR Alert Manifest._
_Signal types: SQR = Azure Monitor Scheduled Query Rule (KQL). Metric = native Azure Monitor Metric Alert._

### Action groups

| Name | Receivers | Trigger condition |
| --- | --- | --- |
| `ag-critical` | PagerDuty on-call + Teams `#ops-alerts` | Sev 0 — system down |
| `ag-deadline` | PagerDuty on-call + Teams `#ops-alerts` + email ops-team | Sev 1 — objection deadline at risk |
| `ag-billing` | Email ops-team + SMS to billing lead | Sev 1 — data accuracy NFR |
| `ag-warning` | Teams `#ops-alerts` only | Sev 2 — degraded, not down |

### Alert rules

| # | Name | NFR target | Signal | Condition (prod) | Condition (pilot) | Sev | Freq | Window | Action |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `latency-otp-p95` | OTP send P95 | SQR | P95 > 200 ms | P95 > 400 ms | 2 | 1 min | 5 min | `ag-warning` |
| 2 | `latency-property-p95` | Property lookup P95 | SQR | P95 > 100 ms | P95 > 300 ms | 2 | 1 min | 5 min | `ag-warning` |
| 3 | `latency-bill-p95` | Bill fetch P95 | SQR | P95 > 150 ms | P95 > 500 ms | 2 | 1 min | 5 min | `ag-warning` |
| 4 | `latency-objection-p95` | Objection submit P95 | SQR | P95 > 300 ms | P95 > 400 ms | 1 | 1 min | 5 min | `ag-deadline` |
| 5 | `latency-notification-p95` | Notification list P95 | SQR | P95 > 150 ms | P95 > 400 ms | 2 | 1 min | 5 min | `ag-warning` |
| 6 | `availability-outage` | Availability (immediate) | SQR | success\_rate = 0 for 10 min | success\_rate = 0 for 15 min | 0 | 1 min | 10 min | `ag-critical` |
| 7 | `availability-sla-breach` | 30-day SLA | SQR | rolling 30 d < 99.9% | rolling 30 d < 99.0% | 1 | 1 h | 30 d | `ag-warning` |
| 8 | `data-accuracy-estimate-streak` | Data accuracy (critical NFR) | SQR | any account ≥ 2 consecutive estimates | any pilot account ≥ 2 | 1 | 1 h | 1 h | `ag-billing` |
| 9 | `infra-dtu-saturation` | SQL capacity headroom | Metric | avg DTU > 80% for 15 min | avg DTU > 80% for 15 min | 2 | 5 min | 15 min | `ag-warning` |
| 10 | `infra-redis-load` | Redis capacity headroom | Metric | avg server\_load > 80% for 10 min | avg server\_load > 80% for 10 min | 2 | 5 min | 10 min | `ag-warning` |
| 11 | `infra-connection-pool-errors` | Prisma pool (28/30 limit) | SQR | > 5 pool timeout exceptions in 5 min | > 5 pool timeout exceptions in 5 min | 1 | 1 min | 5 min | `ag-deadline` |

**Azure Monitor severity:** 0 = Critical · 1 = Error · 2 = Warning.

### Data accuracy alert — required application telemetry (alert 8)

Alert 8 requires bill-service to emit a custom Application Insights event. Without this
instrumentation the data accuracy NFR has no monitoring signal.

bill-service emits `EstimatedReadStreak` when it detects ≥ 2 consecutive estimated reads
for an account. Call the check inside the `GET /bill/account/:accountId` handler after
fetching the bill list:

```typescript
// bill-service — call after fetching bills for an account
function checkEstimateStreak(bills: Bill[], accountId: string): void {
  let streak = 0
  for (const bill of [...bills].sort((a, b) =>
    b.billingPeriodStart.localeCompare(a.billingPeriodStart)
  )) {
    if (bill.readType === 'E') streak++
    else break
  }
  if (streak >= 2) {
    telemetryClient.trackEvent({
      name: 'EstimatedReadStreak',
      properties: {
        accountId,
        consecutiveCount: String(streak),
        latestBillId: bills[0].id,
        billingPeriodStart: bills[0].billingPeriodStart,
      },
    })
  }
}
```

KQL for alert 8:

```kusto
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

On fire: ops verifies the flagged account against the physical statement. At pilot scale
(3 test accounts) this is a phone call. At production scale this feeds a verification
queue.

### Dashboard metrics (not alerts)

- `requests/duration` P95 per operation name — 24h rolling (Application Insights)
- `dtu_consumption_percent` — 24h rolling (Azure SQL)
- `server_load` — 24h rolling (Azure Cache for Redis)
- Redis cache miss ratio — spike during social spike warmup is expected; persistent elevation after 3 min is a cache invalidation bug
- `consecutiveEstimateCount` from `customEvents` — tracks accounts approaching catch-up bill risk
