# EasyRates — Back-of-Envelope Capacity Planning
Generated: 2026-06-19

## Peak-Load Scenario

The worst-case load event is not statement day or payment deadline — it is a WhatsApp-driven
social spike. Emfuleni's billing accuracy problem is driven by estimated meter readings that
accumulate over months, then trigger a large catch-up bill when an actual reading is taken.
When a catch-up bill lands, ratepayers photograph it and circulate it on community WhatsApp
groups. Within 15 minutes, a significant fraction of registered users hits the account view
endpoint simultaneously. This spike arrives with zero advance warning — it cannot be
pre-scaled. The architecture must absorb it statically from a cold start.

Key unknowns at time of writing: IDP 2024/25 PDF is binary-encoded and inaccessible; the
250,000 ratepayer figure is a Census 2022 derivation, not an IDP-stated figure. Actual app
adoption will be available after pilot launch. All estimates should be revised when real data
arrives.

---

## Load Anchor

> **Peak concurrent sessions (production): 5,000**
> **Peak concurrent sessions (pilot): 500**

These are the single most important outputs of this document. Every container resource limit
(plan/08), latency target (plan/05), Azure tier choice, and Redis allocation is sized against
this figure. Neither plan may derive its own session estimate.

Basis: 20% of registered users simultaneously in the 15-minute spike peak.
- Production: 25,000 registered users × 20% = 5,000
- Pilot: 2,500 registered users × 20% = 500

Normal billing-day peak (non-spike): ~375 concurrent in production (10% of 3× normal DAU).
The 5,000 figure is the design anchor because the spike is the harder problem.

---

## Estimates

All capacity metrics in one table. Pilot = 2,500 registered users at 1% adoption.
Production = 25,000 registered users at 10% adoption. Both columns are at 12 months
post-launch. Every number has a source or assumption stated in the rightmost column.

| Metric | Pilot | Production | Source / Assumption |
| --- | --- | --- | --- |
| Consumer account base | — | **250,000** | Census 2022: 945,650 pop ÷ 3.2 avg HH size = ~295,500 HH × 90.1% formal dwelling rate × ~85% registration rate. Midpoint of 225,000–270,000 range. IDP 2024/25 PDF inaccessible (binary-encoded). |
| App adoption % | **1%** | **10%** | Pilot: 2 wards in scope (~12,500 accounts); 20% of in-scope accounts register with active municipal outreach. Production: 10% steady-state; consistent with SA municipal app benchmarks (Cape Town CityApp, eThekwini). |
| Registered users | **2,500** | **25,000** | 250,000 × adoption % (pilot 1%; production 10%). |
| Daily active users (DAU) | **125** | **1,250** | 5% of registered users per day. Ratepayers check account ~1–2× per month; 5% DAU ≈ 1.5 sessions/month distributed across 30 days. |
| **Peak concurrent sessions** | **500** | **5,000** | **20% of registered users in same 15-minute window. Social spike — WhatsApp photo of catch-up bill circulated in community groups — is the design case. No advance warning; vertical ramp. Normal billing-day peak (production): ~375 concurrent.** |
| DB rows: User | 2,500 | 25,000 | One per registered ratepayer at month 12. |
| DB rows: Property | 3,000 | 30,000 | 1.2 properties per user. Most own one; small fraction own 2+ as landlords or investors. |
| DB rows: Account | 9,000 | 90,000 | 3 service accounts per property: water, electricity, property rates. Sanitation bundled with water in most Emfuleni tariff structures. |
| DB rows: Bill | 108,000 | 1,080,000 | 1 bill per service account per month × 12 months. (3 accounts × users × 12.) |
| DB rows: BillLineItem | 540,000 | 5,400,000 | 5 line items per bill: standing charge, consumption units, VAT, current arrears, catch-up charge. Volume table — index strategy in plan/06. |
| DB rows: Objection | 250 | 2,500 | 10% of registered users raise 1 formal objection per year. Consistent with Emfuleni billing dispute prevalence given the estimated-meter-read error rate. |
| DB rows: EvidenceFile | 750 | 7,500 | 3 metadata rows per objection (meter photo, disputed bill, supporting doc). Actual files in Azure Blob Storage (see storage row). |
| DB rows: OTPAttempt | 39,000 | 390,000 | 1 OTP/login × 12 months × users × 1.3 retry factor. Implement 30-day TTL purge → rolling ~3,300 (pilot) / ~33,000 (production) active rows. |
| DB rows: Notification | 90,000 | 900,000 | 3 notifications/user/month (bill issued, payment due, dispute status update) × 12 months. Volume table. Implement 90-day retention → rolling ~22,500 (pilot) / ~225,000 (production) active rows. |
| Evidence file storage/year | ~2.25 GB | ~22.5 GB | Objections × 3 files × 3 MB avg (mobile photos 2–5 MB; PDF scans 1–3 MB). Not in Azure SQL. Azure Blob Storage: LRS pilot, GRS production. Cumulative 3 years production: ~67.5 GB. |

> **Design anchor for plan/05 and plan/08: peak concurrent sessions = 5,000 (production) / 500 (pilot).
> Neither downstream plan may derive its own session estimate — this row is the single source of truth.**

### Read/write ratio per service

Access pattern does not differ between pilot and production — it is determined by the
nature of the operation, not the user count. Both phases use these ratios.

| Service | Read % | Write % | Notes |
| --- | --- | --- | --- |
| auth-service | 90% | 10% | Token validation (read) >> registration, refresh, logout (write). |
| otp-service | 50% | 50% | Generate (write) + verify-then-consume (read+write); symmetric per login cycle. |
| property-service | 98% | 2% | Property details change only on valuation roll updates or ownership transfers. Viewed on every account screen load. |
| account-service | 95% | 5% | Balance/status viewed frequently; updated on payment receipt or account status change only. |
| bill-service | 97% | 3% | One write per bill per month during the billing run; many reads per bill across the month. Monthly flow ratio is ~70/30; cumulative ratio over a bill's lifetime (read many times after written once) is 90–97%. Caching conclusion unchanged either way. |
| objection-service | 60% | 40% | Submission days: 80% write (create, upload, status update); status-tracking days: 80% read. Season average: 60/40. |
| notification-service | 30% | 70% | Bulk dispatch writes during billing run (~3,000 pilot / ~25,000 production at once); inbox reads spread over the month. |

Caching implication: property-service (98% read) and bill-service (97% read) are the
primary Redis cache candidates; data changes at most once per month per record.
auth-service token validation is also cache-eligible. OTP state, live billing totals,
and objection submission status must never be cached.

---

## Azure Cost Estimates

Prices are East US pay-as-you-go (June 2026). South Africa North carries a ~15% premium
over East US for compute and PaaS services; SA North column applies this factor.
Sources: nops.io (Azure SQL DTU), pump.co (App Service), cloudpricecheck.com (Redis),
azure.microsoft.com (Blob Storage).

### Pilot tier

| Component | Tier | Specs | East US/month | SA North/month |
| --- | --- | --- | --- | --- |
| Azure SQL | Basic | 5 DTU, 2 GB max | $4.90 | ~$5.60 |
| App Service Linux | B1 × 1 plan | 1 vCPU, 1.75 GB RAM (all 7 services share) | $13.00 | ~$14.95 |
| Azure Cache for Redis | C0 Basic | 250 MB, no replication | $16.06 | ~$18.47 |
| Blob Storage | LRS Hot | ~5 GB at month 12 | $0.10 | ~$0.12 |
| **Total pilot** | | | **~$34/month** | **~$39/month** |

Assumption: All 7 Node.js services share one B1 plan. Viable at pilot load (500 concurrent
max); 1 vCPU + 1.75 GB RAM is tight but Node.js I/O event-loop handles this at pilot scale.
Redis C0 has no replication — acceptable for pilot (OTP data is ephemeral; cache is
reconstructible from DB on restart).

### Production tier

| Component | Tier | Specs | East US/month | SA North/month |
| --- | --- | --- | --- | --- |
| Azure SQL | S2 Standard | 50 DTU, 250 GB max | $74.00 | ~$85.10 |
| App Service Linux | P1v3 × 3 plans | 2 vCPU, 8 GB RAM per plan; 7 services across 3 plans | $372.00 | ~$427.80 |
| Azure Cache for Redis | C1 Standard | 1 GB, replicated (HA) | $50.37 | ~$57.93 |
| Blob Storage | GRS Hot | ~25 GB at month 12 | $1.00 | ~$1.15 |
| **Total production** | | | **~$497/month** | **~$572/month** |

Service grouping across 3 plans: [auth, otp, property] · [account, bill] · [objection, notification].
Each P1v3 plan can autoscale; 1 additional instance per plan = +$124/plan during social spike
(billed per minute). Full 3-plan spike: +$372 for the duration of the event.

### Notes and upgrade paths

**SQL S2 → S3:** S3 (100 DTU, 250 GB, ~$147/month East US) when Azure Monitor shows DTU
saturation above 80% sustained. No data migration required — online scaling.

**ACI alternative for production:** 7 containers at 0.5 vCPU / 1 GB each ≈ $150/month
baseline (cheaper than 3 × P1v3). Autoscale adds ~$21/container/month per extra instance.
Requires Azure Container Registry Basic (~$5/month). Viable if CI/CD is containerised.

**South Africa North availability:** Azure SQL (all DTU tiers), App Service, Redis Cache,
and Blob Storage are all confirmed available in South Africa North. Redis C0/C1 are
available (Classic tier); check Azure Portal for Managed Redis availability in SA North
before upgrading beyond C1.

**Twilio OTP SMS (outside Azure, billed separately):**

- Pilot: ~2,500 users × 1 OTP/month × 1.3 retries × $0.0065/SMS ≈ **$21/month**
- Production: ~25,000 users × 1 OTP/month × 1.3 retries × $0.0065/SMS ≈ **$211/month**

**Total cost of ownership (SA North, including Twilio):**

- Pilot: ~$39 + $21 = **~$60/month**
- Production: ~$572 + $211 = **~$783/month**

---

## Revision notes

- Ratepayer base (250,000): revise when IDP 2024/25 or 2026/27 PDF becomes readable or
  when the municipality provides a direct account count.
- Adoption curve: revise after pilot launch with actual registration data.
- OTPAttempt and Notification row counts: implement a purge/TTL policy before month 3 to
  keep table sizes manageable.
- EvidenceFile storage: re-estimate at month 6 pilot with actual objection submission rate.

## Verification record (2026-06-20)

Sanity check completed against the following standard: does each estimate fit a mid-sized
SA district municipality's self-service app, or does it imply national-platform scale?

**Result: no number off by 10×. No revisions made.**

Sensitivity summary — variables with meaningful uncertainty:

| Variable | Envelope | Realistic range | Direction to err | Review trigger |
| --- | --- | --- | --- | --- |
| Production app adoption | 10% (25,000 users) | 5–15% | High side (capacity planning) | Month 3 pilot registration data |
| Peak spike % in 15-min window | 20% of registered | 10–30% | High side (spike is unscheduled) | First social spike event |
| Peak concurrent (production) | 5,000 | 1,250–7,500 | High side | As above |
| Bill-service cumulative read ratio | 97% (lifetime); ~70% (monthly flow) | — | Caching conclusion unchanged | Not a revision trigger |

**Architecture consistency check:** 3 × P1v3 App Service (6 vCPU, 24 GB) with Redis
absorbing ~95%+ of read traffic delivers ~22 req/sec sustained and ~167 req/sec at burst
during a 5,000-user spike. Both are within capacity. Autoscale to 6 × P1v3 covers the
7,500-user variant if adoption reaches 15%.

**External review pending:** peak concurrent figure (5,000) and production adoption rate
(10%) should be shared with a practitioner who has seen actual usage data from a comparable
SA municipality (eThekwini, NMBM, or Tshwane self-service). That review is not a blocker
for plan/05 and plan/08 — the 5,000 anchor stands until actual pilot data arrives.
