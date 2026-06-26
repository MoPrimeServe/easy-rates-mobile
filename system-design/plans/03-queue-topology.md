# 🔁 Queue Topology

## Background

The queue topology governs which parts of the system are resilient to worker failure
and which are not. A wrong choice here cascades: it affects the data model (job-state
records), the container topology (broker service and worker containers), and the API
contracts (202 vs 200 response shapes). Getting it right means the Flutter client is
never left holding a spinner when a worker crashes.

## Description
Identify all async screen transitions from service-map.md. Evaluate queue/task
technology options against Node.js/TypeScript constraints. Choose one. Document queue
names, producer modules, consumer worker functions, message payload schemas, retry
policies, and dead-letter strategy.

## Purpose
To answer: "when a queue worker crashes mid-task, what does the Flutter user
experience?" The correct answer is: "a push notification when the worker recovers and
the task completes." The wrong answer is: "a spinner forever."

## Goal
`easy_rates/system-design/docs/queue-topology.md` — technology decision with scored
rationale, and for every async transition: queue/task name, producer Node.js module,
consumer worker function signature, message payload schema, retry policy, DLQ name, TTL
where applicable.

## Tasks

- [x] ✅ THINK `/socratic "What must be true about our queue for the Flutter client to
  always receive a meaningful response — even when a worker crashes mid-task — and
  which failure modes are we willing to accept vs which must never happen?"`
  ✓ verified (learning/socratic-queue-reliability-flutter-2026-06-19/)
  Done when: the failure modes are enumerated (worker crash, broker unreachable,
  task timeout, duplicate delivery) and each has an explicit accept/mitigate/eliminate
  decision in writing.
  Downstream: these enumerated failure modes become the "Failure Scenarios" section
  of queue-topology.md — write them there before the DECIDE task picks a technology,
  so the technology choice is evaluated against real failure modes, not hypotheticals.

- [x] ✅ LEARN `/unpack "BullMQ vs RabbitMQ for Node.js/TypeScript — task routing, retry
  with exponential backoff, dead-letter queues, visibility timeout, at-least-once vs
  exactly-once delivery, Podman image availability, and ops overhead at small scale"`
  ✓ verified (learning/unpack-bullmq-vs-rabbitmq-2026-06-19/)
  Done when: you can score each option on five criteria (Node.js/TypeScript integration
  maturity, retry/DLQ support, local dev experience, ops simplicity, Podman image) and
  explain why the winner scores higher.

- [x] ✅ LIST Pull every async transition from service-map.md. For each, fill in:
  Producer app | Consumer task | Message payload (field names + types) |
  Acceptable delay SLA | Failure behaviour if consumer is down.
  ✓ stated (5 transitions; all 5 columns filled; output produced in conversation)
  Done when: every async transition from service-map.md is in this table with all
  five columns filled.

- [x] ✅ DECIDE Choose one technology. Write a scored comparison table (≥ 3 criteria,
  each scored 1–3) followed by a one-paragraph rationale. If BullMQ is chosen:
  identify which queue pattern applies to each task type:
  `Queue` + `Worker` — standard job with retry
  `FlowProducer` — chained jobs with dependencies
  and justify the choice per async transition.
  ✓ verified (scored table + BullMQ rationale in docs/queue-topology.md)
  Done when: decision is written; rationale is specific; a colleague could implement
  the chosen technology without asking you anything.
  Downstream: the chosen BullMQ queue/worker pattern for each task feeds plan/08
  (container topology) directly — the broker container image, port, named volume,
  and Bull Board dashboard port all come from the pattern chosen here. Record the
  exact Docker image tag (e.g. `redis:7-alpine`) so plan/08 copies it verbatim.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/queue-topology.md` — one section
  per async transition covering: task/queue name, producer, consumer function
  signature, payload schema, retry policy (max retries, backoff strategy), DLQ name,
  TTL, and the technology rationale as a preamble section.
  ✓ verified (docs/queue-topology.md, 18 KB; engagement checks 6/7 pass)
  Done when: every async transition from the LIST task appears in the document with
  all fields complete.

- [x] ✅ VERIFY Simulate the hardest failure scenario in writing: a worker dequeues
  an OTP-dispatch task and crashes before calling Twilio. Walk through:
  (a) Does the message return to the queue, or is it lost?
  (b) Is there a retry? After how long?
  (c) Does the Flutter OTP screen get any feedback, or does it wait for TTL expiry?
  Document the answers in queue-topology.md under a "Failure Scenarios" section.
  ✓ verified (Failure Scenarios section in docs/queue-topology.md; 0 TBD/depends)
  Done when: all three questions have specific, implementation-level answers; no
  answer says "TBD" or "depends."

## Recommended skill
▶ `/socratic` ✅ — THINK task; enumerating failure modes before choosing a technology
   is the only way to evaluate the trade-offs honestly.
   alt: `/unpack` ✅ — BullMQ vs RabbitMQ if the options aren't already well understood.

## Engagement Instructions

```bash
# 1. File exists
ls -lh easy_rates/system-design/docs/queue-topology.md
# Expected: present, size > 3 KB

# 2. BullMQ named as chosen technology (per ADR-001)
grep -i "BullMQ" easy_rates/system-design/docs/queue-topology.md | wc -l
# Expected: ≥ 3 mentions (decision section + queue definitions)

# 3. All 3 confirmed async transitions have queue entries
for task in "otp-dispatch" "submission-notification" "status-change-notification"; do
  printf "%-32s %s mentions\n" "$task:" \
    "$(grep -c "$task" easy_rates/system-design/docs/queue-topology.md)"
done
# Expected: each ≥ 1

# 4. Each queue entry has all 7 required fields
for field in "payload" "retry" "DLQ\|dead.letter" "TTL" "producer" "consumer" "backoff"; do
  printf "%-20s %s lines\n" "$field:" \
    "$(grep -icE "$field" easy_rates/system-design/docs/queue-topology.md)"
done
# Expected: each field ≥ 1 line

# 5. Failure scenarios section present — OTP-crash case answered
grep -iE "crash|failure scenario|worker.*fail" \
  easy_rates/system-design/docs/queue-topology.md | wc -l
# Expected: ≥ 3

# Confirm all 3 OTP-crash questions answered (no TBD/depends)
grep -iE "TBD|depends" easy_rates/system-design/docs/queue-topology.md
# Expected: 0 results

# 6. Redis image tag recorded for plan/08 to copy
grep -iE "redis:[0-9]|redis:alpine|redis:[a-z0-9]+-alpine" \
  easy_rates/system-design/docs/queue-topology.md
# Expected: ≥ 1 line with a specific image tag

# 7. Async transition count matches service-map.md
SD_ASYNC=$(grep -c "Async" easy_rates/system-design/docs/service-map.md 2>/dev/null || echo "0")
QT_TASKS=$(grep -cE "^#{2,3} " easy_rates/system-design/docs/queue-topology.md)
echo "service-map Async rows: $SD_ASYNC | queue-topology task sections: $QT_TASKS"
# Expected: QT_TASKS >= SD_ASYNC (every Async transition has a section)
```

Gate: checks 1–6 must pass before this plan closes.
Check 7 is a cross-plan consistency gate — run it again after service-map.md is
finalised in plan/01. The Redis image tag from check 6 is copied verbatim into
plan/08's container inventory.
