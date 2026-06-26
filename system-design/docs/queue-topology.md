# Queue Topology

## Technology Decision: BullMQ on Redis

**Chosen technology:** BullMQ (`bullmq` npm package) on Redis
**Broker image (copy verbatim into plan/08):** `redis:7-alpine`
**Dashboard:** Bull Board (`@bull-board/express`), dev-only, port 3001

### Scored comparison

| Criterion | BullMQ (Redis) | RabbitMQ |
|---|---|---|
| TypeScript / Node.js integration maturity | 3 — `Queue<T>` and `Worker<T>` generics; typed `job.data` throughout; no community-lag types | 2 — `amqplib` has no official types; `@types/amqplib` is community-maintained |
| Retry + DLQ support | 3 — declarative per-queue: `attempts`, `backoff`, `removeOnFail`; failed state is the DLQ | 3 — dead-letter exchanges + per-message TTL are mature; requires manual exchange/binding config |
| Local dev / Podman experience | 3 — `redis:7-alpine` at ~30 MB; one container covers broker and future cache | 2 — `rabbitmq:3-management` at ~220 MB; management UI adds weight; no shared use |
| Ops simplicity at small scale | 3 — queue name is the address; no exchanges, bindings, or routing keys; Bull Board is one `npm` dependency | 2 — AMQP concepts add indirection that is powerful at scale but overhead here |
| Job lock / visibility timeout | 3 — `lockDuration` + heartbeat renewal; stalled jobs auto-detected and re-queued | 2 — nack + requeue achieves the same, but requires explicit consumer code |
| **Total** | **15 / 15** | **12 / 15** |

### Rationale

BullMQ is the correct choice. All five async transitions are leaf operations — dispatch an OTP, push a KYC result, confirm a submission, push a status change, confirm an escalation — with no cross-job dependencies, no fan-out, and no routing requirement beyond "put this job on this queue." RabbitMQ's differentiator is complex routing topology (exchanges, topic bindings, fan-out patterns); nothing in this system needs that. BullMQ's `Queue + Worker` pattern covers all five transitions with one mental model: enqueue a typed job, process it in a Worker, retry with exponential backoff on failure, move to the failed state (DLQ) on exhaustion. TypeScript ergonomics are first-class, retry and DLQ policies are declarative, the `redis:7-alpine` broker image is 30 MB and doubles as a cache layer later, and Bull Board provides real-time job visibility at zero infrastructure cost. Switching away from BullMQ after launch would require rewriting all five Worker definitions, swapping the broker container, and retesting every retry scenario — estimated three days of work and a deployment window.

### BullMQ pattern applied

All five async transitions use **`Queue + Worker`** (standard job with retry). `FlowProducer` is not used — no transition has a downstream dependent job. All five are terminal leaf operations; once the Worker sends the OTP or push, there is no next job to chain.

### Visibility timeout equivalent

BullMQ uses a job lock rather than a visibility timeout. When a Worker takes a job it acquires a Redis lock with TTL = `lockDuration` (configured: 30 000 ms). The Worker renews this lock every `lockDuration / 2` via a heartbeat. If the Worker crashes, the heartbeat stops, the lock expires, and BullMQ's stalled-job checker (runs every `stalledInterval`, configured: 30 000 ms) detects the job still in the active set with an expired lock and moves it back to `waiting`. This re-queued job counts as a new attempt against `maxAttempts`. Worst-case detection latency: 60 seconds (lock TTL + one checker interval).

---

## Failure Scenarios

### Scenario 1 (hardest): Worker crashes after dequeuing `otp-dispatch`, before calling Twilio

**Setup.** auth-service enqueues an `otp-dispatch` job. The otp-service Worker dequeues it and crashes immediately — before the Twilio API call is issued.

**(a) Does the message return to the queue, or is it lost?**

The job is not lost. BullMQ tracks all active jobs in a Redis sorted set keyed by `otp-dispatch:active`. When the Worker crashes, the job lock (`otp-dispatch:lock:<jobId>`) expires after `lockDuration` (30 s). The stalled-job checker next runs within `stalledInterval` (30 s) and finds the job in the active set with an expired lock. It moves the job back to `waiting` and increments `attemptsMade`. The Redis persistence (AOF or RDB) ensures the job survives a Redis restart as well.

**(b) Is there a retry? After how long?**

Yes. The job re-enters `waiting` within 30–60 seconds of the crash. BullMQ then applies the exponential backoff before the next attempt: attempt 2 waits 5 000 ms × 2¹ = 10 000 ms; attempt 3 waits 5 000 ms × 2² = 20 000 ms. Worst-case time to first retry delivery: ~90 seconds (60 s detection + 30 s backoff). A 5-minute OTP TTL gives ~4 minutes of headroom — ample for three attempts.

Before each retry the Worker checks `job.data.expires_at`. If the OTP has not expired, Twilio is called. If the OTP has expired, the Worker returns without throwing — BullMQ marks the job `completed` (intentional drop, not a failure), the job does not count against `maxAttempts`, and no DLQ entry is created.

**(c) Does the Flutter OTP screen get any feedback, or does it wait for TTL expiry?**

The Flutter OTP screen has no direct connection to the queue. It shows "Check your phone" and waits. If the OTP does not arrive within a user-facing timeout (~60 s), the user taps "Resend OTP," which calls `POST /otp/resend`. auth-service generates a new code, creates a fresh `otp-dispatch` job with a new `expires_at`, and the original stalled job either delivers (both codes are valid until their respective `expires_at`) or is dropped on recovery. Both outcomes are safe: the user has a working code and the old code, if delivered late, is still valid.

### Scenario 2: Worker crashes mid-`status-change-notification` job

**Setup.** status-service enqueues a `status-change-notification` job (`more_info_requested`). The notification-service Worker dequeues it and crashes before sending the FCM push.

**(a) Message lost?** No — same stalled-job mechanism as Scenario 1. Job returns to `waiting` within 60 seconds.

**(b) Retry?** Yes, up to 5 attempts with 30 000 ms exponential backoff. No TTL constraint — the status change notification must be delivered regardless of age.

**(c) Flutter feedback?** The user is not actively waiting on this push (they may have the app in the background). They discover the status change on their next manual poll of `GET /objections/:ref/status`. The push notification is the proactive path, not the sole discovery path. Worker failure here degrades to polling — no data is lost.

---

## Queue Definitions

### 1. `otp-dispatch`

| Field | Value |
|---|---|
| Task name | `otp.dispatch` |
| Producer module | `src/modules/auth` |
| Consumer module | `src/modules/otp` |
| Trigger | `register/start` (registration); `login` (login); OTP resend request |
| Max retries (attempts) | 3 |
| Backoff strategy | Exponential, initial delay 5 000 ms (5 s → 15 s → 45 s) |
| DLQ | BullMQ failed state within `otp-dispatch`; monitor via Bull Board or `queue.getFailed()` |
| TTL | Governed by `expires_at` in payload (checked in Worker before each attempt); not enforced at queue level |
| Acceptable delay SLA | < 30 seconds |

**Consumer function signature:**
```typescript
import { Job, Worker } from 'bullmq';

async function processOtpDispatch(job: Job<OtpDispatchPayload>): Promise<void> {
  if (new Date(job.data.expires_at) <= new Date()) return; // intentional drop — do not throw
  await twilio.messages.create({
    to: job.data.phone,
    body: buildOtpMessage(job.data.otp_purpose, job.data.code),
    from: process.env.TWILIO_PHONE_NUMBER,
  });
}

new Worker<OtpDispatchPayload>('otp-dispatch', processOtpDispatch, workerOptions);
```

**Payload schema:**
```typescript
interface OtpDispatchPayload {
  user_id?:    string;                              // UUID — absent for REGISTRATION (no User yet)
  phone:       string;                              // E.164, e.g. +27821234567
  otp_purpose: 'REGISTRATION' | 'LOGIN';
  code:        string;                              // 6-digit numeric string, e.g. '048321'
  expires_at:  string;                              // ISO 8601, e.g. '2026-06-19T10:35:00Z'
}
```

---

### 2. `kyc-notification`

| Field | Value |
|---|---|
| Task name | `notification.kyc_status_change` |
| Producer module | `src/modules/auth` (on municipality webhook receipt) |
| Consumer module | `src/modules/notification` |
| Trigger | `kyc_status` transitions to `kyc_approved` or `kyc_rejected` |
| Max retries (attempts) | 5 |
| Backoff strategy | Exponential, initial delay 30 000 ms (30 s → 60 s → 120 s → 240 s → 480 s) |
| DLQ | BullMQ failed state within `kyc-notification`; standard operator alert |
| TTL | None — deliver regardless of age; KYC status is persisted in the DB regardless |
| Acceptable delay SLA | < 2 minutes |

**Consumer function signature:**
```typescript
async function processKycNotification(job: Job<KycNotificationPayload>): Promise<void> {
  await fcm.send({
    token: job.data.push_token,
    notification: buildKycPush(job.data.status, job.data.rejection_reason),
  });
}

new Worker<KycNotificationPayload>('kyc-notification', processKycNotification, workerOptions);
```

**Payload schema:**
```typescript
interface KycNotificationPayload {
  user_id:           string;                            // UUID
  status:            'kyc_approved' | 'kyc_rejected';
  rejection_reason?: string;                            // present only when status = 'kyc_rejected'
  push_token:        string;                            // FCM device token
}
```

---

### 3. `submission-notification`

| Field | Value |
|---|---|
| Task name | `notification.objection_submitted` |
| Producer module | `src/modules/objection` (on `draft → submitted` transition) |
| Consumer module | `src/modules/notification` |
| Trigger | `Objection.status` transitions from `draft` to `submitted` |
| Max retries (attempts) | 5 |
| Backoff strategy | Exponential, initial delay 30 000 ms |
| DLQ | BullMQ failed state within `submission-notification`; standard operator alert; low severity — reference number is already in the user's hand |
| TTL | None |
| Acceptable delay SLA | < 5 minutes |

**Consumer function signature:**
```typescript
async function processSubmissionNotification(job: Job<SubmissionNotificationPayload>): Promise<void> {
  await Promise.all([
    twilio.messages.create({
      to:   job.data.phone,
      body: buildSubmissionSms(job.data.reference_number, job.data.disputed_items_summary),
      from: process.env.TWILIO_PHONE_NUMBER,
    }),
    sendgrid.send(buildSubmissionEmail(job.data)),
  ]);
}

new Worker<SubmissionNotificationPayload>(
  'submission-notification',
  processSubmissionNotification,
  workerOptions,
);
```

**Payload schema:**
```typescript
interface SubmissionNotificationPayload {
  user_id:                 string; // UUID
  reference_number:        string;
  email:                   string;
  phone:                   string; // E.164
  disputed_items_summary:  string; // human-readable summary for email/SMS body
}
```

---

### 4. `status-change-notification`

| Field | Value |
|---|---|
| Task name | `notification.objection_status_change` |
| Producer module | `src/modules/status` |
| Consumer module | `src/modules/notification` |
| Trigger | `Objection.status` transitions to `more_info_requested`, `upheld`, or `rejected` |
| Max retries (attempts) | 5 |
| Backoff strategy | Exponential, initial delay 30 000 ms |
| DLQ | BullMQ failed state within `status-change-notification`; **elevated** operator alert — `more_info_requested` may carry a user action deadline |
| TTL | None |
| Acceptable delay SLA | < 2 minutes |

**Consumer function signature:**
```typescript
async function processStatusChangeNotification(
  job: Job<StatusChangeNotificationPayload>,
): Promise<void> {
  await Promise.all([
    fcm.send({
      token:        job.data.push_token,
      notification: buildStatusPush(job.data.new_status, job.data.deep_link_path),
    }),
    twilio.messages.create({
      to:   job.data.phone,
      body: buildStatusSms(job.data.new_status, job.data.reference_number),
      from: process.env.TWILIO_PHONE_NUMBER,
    }),
    sendgrid.send(buildStatusEmail(job.data)),
  ]);
}

new Worker<StatusChangeNotificationPayload>(
  'status-change-notification',
  processStatusChangeNotification,
  workerOptions,
);
```

**Payload schema:**
```typescript
interface StatusChangeNotificationPayload {
  user_id:          string;                                            // UUID
  reference_number: string;
  new_status:       'more_info_requested' | 'upheld' | 'rejected';
  email:            string;
  phone:            string;                                            // E.164
  push_token:       string;                                            // FCM device token
  deep_link_path:   string;                                            // e.g. /objections/:ref/status
}
```

---

### 5. `probe-escalation-notification`

| Field | Value |
|---|---|
| Task name | `notification.probe_escalation` |
| Producer module | `src/modules/status` (on 3rd probe submitted against a single objection) |
| Consumer module | `src/modules/notification` |
| Trigger | `probe_count` reaches 3 on an objection |
| Max retries (attempts) | 3 |
| Backoff strategy | Exponential, initial delay 30 000 ms (30 s → 60 s → 120 s) |
| DLQ | BullMQ failed state within `probe-escalation-notification`; standard operator alert; informational only — the escalation action is recorded separately |
| TTL | None |
| Acceptable delay SLA | < 5 minutes |

**Consumer function signature:**
```typescript
async function processProbeEscalationNotification(
  job: Job<ProbeEscalationPayload>,
): Promise<void> {
  await fcm.send({
    token:        job.data.push_token,
    notification: buildEscalationPush(job.data.reference_number, job.data.probe_count),
  });
}

new Worker<ProbeEscalationPayload>(
  'probe-escalation-notification',
  processProbeEscalationNotification,
  workerOptions,
);
```

**Payload schema:**
```typescript
interface ProbeEscalationPayload {
  user_id:          string; // UUID
  reference_number: string;
  probe_count:      3;      // literal type — always 3 at escalation threshold
  push_token:       string; // FCM device token
}
```

---

## BullMQ Configuration Reference

```typescript
import { Queue, Worker, ConnectionOptions, WorkerOptions, QueueOptions } from 'bullmq';

// Broker connection — matches redis:7-alpine container in podman-compose
const redisConnection: ConnectionOptions = {
  host: process.env.REDIS_HOST ?? 'redis',
  port: Number(process.env.REDIS_PORT ?? 6379),
};

// Worker options — shared across all five Workers
const workerOptions: WorkerOptions = {
  connection:       redisConnection,
  lockDuration:     30_000, // Worker holds job lock for 30 s
  stalledInterval:  30_000, // Stalled-job checker runs every 30 s
  maxStalledCount:  1,      // Move to failed state after 1 stall (handles Worker crash)
};

// Queue factory — parameterised per queue
function makeQueue<T>(
  name: string,
  attempts: number,
  backoffDelay: number,
): Queue<T> {
  return new Queue<T>(name, {
    connection: redisConnection,
    defaultJobOptions: {
      attempts,
      backoff:          { type: 'exponential', delay: backoffDelay },
      removeOnComplete: true,
      removeOnFail:     false, // retain failed jobs in DLQ (failed state) for Bull Board
    },
  } satisfies QueueOptions);
}

// Queue instances
export const otpDispatchQueue              = makeQueue<OtpDispatchPayload>('otp-dispatch', 3, 5_000);
export const kycNotificationQueue          = makeQueue<KycNotificationPayload>('kyc-notification', 5, 30_000);
export const submissionNotificationQueue   = makeQueue<SubmissionNotificationPayload>('submission-notification', 5, 30_000);
export const statusChangeNotificationQueue = makeQueue<StatusChangeNotificationPayload>('status-change-notification', 5, 30_000);
export const probeEscalationQueue          = makeQueue<ProbeEscalationPayload>('probe-escalation-notification', 3, 30_000);
```

```typescript
// Bull Board — dev-only, mount on Express app
import { createBullBoard }    from '@bull-board/api';
import { BullMQAdapter }      from '@bull-board/api/bullMQAdapter';
import { ExpressAdapter }     from '@bull-board/express';

const serverAdapter = new ExpressAdapter().setBasePath('/admin/queues');

createBullBoard({
  queues: [
    new BullMQAdapter(otpDispatchQueue),
    new BullMQAdapter(kycNotificationQueue),
    new BullMQAdapter(submissionNotificationQueue),
    new BullMQAdapter(statusChangeNotificationQueue),
    new BullMQAdapter(probeEscalationQueue),
  ],
  serverAdapter,
});

// Mount at http://localhost:3000/admin/queues (dev only — gate behind NODE_ENV check)
if (process.env.NODE_ENV !== 'production') {
  app.use('/admin/queues', serverAdapter.getRouter());
}
```

---

## Summary Table

| Queue name | Producer | Consumer | Attempts | Backoff start | TTL | DLQ alert level |
|---|---|---|---|---|---|---|
| `otp-dispatch` | auth | otp | 3 | 5 000 ms | `expires_at` in payload | monitor only |
| `kyc-notification` | auth | notification | 5 | 30 000 ms | none | standard |
| `submission-notification` | objection | notification | 5 | 30 000 ms | none | standard |
| `status-change-notification` | status | notification | 5 | 30 000 ms | none | **elevated** |
| `probe-escalation-notification` | status | notification | 3 | 30 000 ms | none | standard |
