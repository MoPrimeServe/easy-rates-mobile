# 🏗️ Service Boundaries

## Background
✅ Gate cleared — plan 00 confirmed (screen inventory complete, user sign-off given).

The service map produced here is the backbone every other plan inherits. Queue topology
(plan/03), data model (plan/06), security (plan/07), and API contracts (plan/09) all
use the service names and ownership assignments defined here. Getting the boundaries
wrong compounds through every plan below it.

## Description
For every row in screen-inventory.md, assign one owning service. Draw bounded contexts.
Identify which screen transitions are synchronous (Flutter blocks and waits) vs
asynchronous (Flutter gets a 202 and a later notification). Name the Node.js service
module that implements each service. Validate that no flow requires more than two
synchronous hops.

## Purpose
To answer: "which Node.js service module owns which screen — and how many synchronous
network calls does each user flow require?" A flow with three or more synchronous hops
is a design smell that must be justified or eliminated before any implementation starts.

## Goal
`easy_rates/system-design/docs/service-map.md` — bounded-context diagram (ASCII),
ownership matrix, and a flow-trace table: Screen Transition → Service → Node.js Module →
Endpoint placeholder → Sync/Async → Flutter widget that triggers it.

## Tasks

- [x] ✅ THINK `/socratic "What would have to be true for us to merge two of these
  services in six months — and what would make that impossible? What is the coupling
  we are willing to accept, and what coupling would we regret?"`
  Done when: the cohesion/coupling principle that governs every boundary decision in
  this plan is written in one paragraph.
  Downstream: this paragraph becomes the opening "Design Principles" section of
  service-map.md — write it there before drawing any boundary boxes in WRITE.  ✓ stated

- [x] ✅ LEARN `/unpack "Node.js service modules as bounded contexts — how to structure
  a TypeScript monorepo so each service is a module with its own Prisma models, route
  handlers, and validation, and what that looks like vs a true microservices split"`
  Done when: you understand the monorepo-module pattern and can state the trade-offs
  vs microservices for a pilot-scale municipal app.  ✓ stated

- [x] ✅ ASSIGN For each row in screen-inventory.md, assign exactly one owning service:
  `auth-service | otp-service | property-service | account-service | bill-service |
  objection-service | notification-service | client-only`
  Each service = one Node.js TypeScript module in the project. Name the module now —
  this name must be used unchanged in every plan that follows.
  Done when: every screen-inventory row has a service owner; zero rows say "TBD."  ✓ verified (TBD count = 0 in screen-inventory.md)

- [x] ✅ SYNC-ASYNC For each screen transition in the table: mark Sync or Async.
  Sync = Flutter blocks; a spinner shows; the user cannot proceed until the response
  arrives. Async = Flutter receives 202 immediately; a push notification or status
  poll delivers the result later.
  Identify cross-service calls: when service A must call service B synchronously,
  name both, the data passed, and why it cannot be async.
  Done when: Sync/Async column filled for every transition; cross-service calls
  listed with justification.
  Downstream: every row marked Async becomes a named queue task in plan/03
  (queue topology). Copy the Async rows verbatim into plan/03's LIST task as the
  seed — no async transition in service-map.md may be absent from queue-topology.md.  ✓ verified (13 Async rows, hop table ≥7 lines)

- [x] ✅ WRITE Write `easy_rates/system-design/docs/service-map.md`:
  1. ASCII bounded-context diagram (boxes for each service, arrows for sync calls)
  2. Ownership matrix (service → Node.js module name → screens owned)
  3. Flow-trace table: Screen Transition → Service → Node.js Module →
     Endpoint placeholder → Sync/Async → Flutter widget that triggers it
  Done when: all three sections complete; every screen-inventory row appears in the
  trace table.  ✓ verified (service-map.md 25 KB, 151 rows, all 9 services present)

- [x] ✅ VERIFY Optimality test — for each of the seven Figma flows, trace the happy
  path end-to-end and count synchronous service hops. Record in a table:
  Flow | Hop count | Services crossed.
  Flag any flow with more than two synchronous hops as a design smell. Either
  redesign the boundary or write an explicit justification.
  Also: count pink diamonds in screen-inventory.md. Count endpoint placeholders in
  service-map.md. Numbers must match — zero orphan diamonds.
  Done when: hop-count table written; all smells resolved or justified; diamond
  count matches endpoint-placeholder count.  ✓ verified (no 3+ hop smells, all checks pass)

## Recommended skill
▶ `/socratic` ✅ — THINK task; the merge/split question is the heart of bounded-context
   design and surfaces coupling you haven't noticed yet.
   alt: `/unpack` ✅ — Node.js TypeScript monorepo structure if the module-as-service
   pattern is new.

## Engagement Instructions

```bash
# 1. service-map.md exists
ls -lh easy_rates/system-design/docs/service-map.md
# Expected: present, size > 3 KB

# 2. All 9 service modules named and present in the file
for svc in "auth-service" "otp-service" "property-service" "queue-consumer" \
           "bill-service" "objection-service" "notification-service" \
           "status-service" "account-service"; do
  printf "%-25s %s mentions\n" "$svc:" \
    "$(grep -c "$svc" easy_rates/system-design/docs/service-map.md)"
done
# Expected: every service ≥ 1 mention

# 3. No TBD service owners remain in screen-inventory.md
grep -c "TBD" easy_rates/system-design/docs/screen-inventory.md
# Expected: 0

# 4. Hop-count table present and no unexcused flow exceeds 2 synchronous hops
grep -iE "hop|synchronous" easy_rates/system-design/docs/service-map.md | wc -l
# Expected: ≥ 7 lines (one per flow minimum)

grep -iE "\b[3-9]\b.{0,10}hop|hop.{0,10}\b[3-9]\b" \
  easy_rates/system-design/docs/service-map.md
# Expected: 0 results (or each result has a "justification" on the same/next line)

# 5. ASCII bounded-context diagram present
grep -cE "\+[-]+\+|[|].*service|auth|otp|property" \
  easy_rates/system-design/docs/service-map.md
# Expected: ≥ 5 lines

# 6. Flow-trace table covers all 47 Figma transitions
grep -c "^|[^-]" easy_rates/system-design/docs/service-map.md
# Expected: ≥ 47 rows

# 7. Async rows seeded into plan/03 LIST task
grep -c "Async" easy_rates/system-design/docs/service-map.md
# Expected: ≥ 3 (OTP dispatch, notification on submit, status-change notification
#                 are the minimum confirmed async transitions)
```

Gate: checks 1–6 must pass before VERIFY closes.
Check 7 is a cross-plan consistency check — the Async row count here must match
the queue-task count in queue-topology.md once plan/03 is complete.
Node.js module names locked here are immutable across all downstream plans
(03, 06, 07, 08, 09, 10) — any rename requires updating every reference.
