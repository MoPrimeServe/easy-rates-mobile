# Service Map

## Design Principles

A service module earns its own boundary when any one of three conditions holds: it has an independent audit trail — its questions must be answerable without entangling another module's state; it changes for a different reason than its neighbors — a provider swap, a tariff rule change, an identity policy update each earn a distinct boundary; or it is reused across more than one flow. Two modules may merge only when none of these conditions holds for either. Across boundaries, synchronous inter-service calls are acceptable exactly when one service cannot complete its transaction without the other's answer — the OTP verify call that gates session creation is the canonical example. Every other cross-service call is asynchronous. The coupling we accept is a narrow synchronous interface at a transaction gate. The coupling we regret is a synchronous call made for information that could have arrived later, and any dependency that entangles one service's audit log with another's.

---

## Bounded-Context Diagram

> **Reconciled 2026-06-21 (api-contracts, plan/09):** `status-service` was dissolved. Its
> resident-facing TRACKING routes moved into **objection-service** (the `objection → status`
> call is now intramodule), History of Objections into **account-service**, and the inbound
> municipal resolution webhook became the new **municipality-service**. Roster stays nine.

```text
+- Flutter (mobile) --+         +- Municipal back-office -+
|  Dart / Widgets      |        |  (CRM / clerk portal)   |
+---------------------+         +------------+------------+
          | HTTPS                            | webhook (X-Municipal-Webhook-Secret)
          v                                  v
+------------------------------------------------------------------+
|  Node.js / Express  (pnpm workspace — nine service modules)      |
|                                                                  |
|  +----------+  --sync:verifyOtp-->  +---------+                 |
|  |   auth   |                       |   otp   |                 |
|  +----------+                       +---------+                 |
|       | enqueue                          | enqueue              |
|       +-------------------+-------------+                       |
|                           v                                      |
|                  +----------------+  <-- also from: objection,   |
|                  | queue-consumer |      municipality            |
|                  +----------------+                             |
|                           | dispatch                            |
|                           v                                      |
|                  +--------------+                               |
|                  | notification |                               |
|                  +--------------+                               |
|                                                                  |
|  +------+  <--sync:getCharge--  +-------------------------+     |
|  | bill |                       | objection               |     |
|  +------+                       | (owns tracking: status, |     |
|                                 |  probe, escalate, close)|     |
|                                 +------------+------------+     |
|                                              ^ sets status       |
|  +---------+  +---------+        +--------------+               |
|  | property|  | account |        | municipality |               |
|  +---------+  +---------+        +--------------+               |
+------------------------------------------------------------------+
          |
          v
     Azure SQL (Prisma)
```

**Sync arrows** (service A calls service B as a function — zero network hop):

- `auth` → `otp`: OTP code verification (login and registration phone-verify flows; ADR-002 passwordless)
- `objection` → `bill`: fetch charge details when creating an objection draft

(The former `objection` → `status` transition on MORE_INFO document upload is now **intramodule** within objection-service — status-service was dissolved.)

**Async arrows** (enqueued via queue-consumer, no Flutter wait):

- `auth` → `queue-consumer` → `otp`: OTP dispatch (registration, login, resend)
- `auth` → `queue-consumer` → `notification`: KYC status change push
- `objection` → `queue-consumer` → `notification`: objection submitted confirmation (email + SMS); probe escalation (3rd probe)
- `municipality` → `queue-consumer` → `notification`: status change notifications (more_info, upheld, rejected) on inbound CRM webhook

---

## Ownership Matrix

| Service | Node.js Module | Screens Owned |
| --- | --- | --- |
| auth-service | `src/modules/auth` | App Launch Token Check, Log In, Sign Up, OTP Sent (registration), Upload Proof of Address, Awaiting KYC Approval, KYC Rejected, Log Out |
| otp-service | `src/modules/otp` | Verify Phone OTP, Verify Login OTP, OTP Valid? (both branches), OTP Expired / Resend |
| property-service | `src/modules/property` | Enter Account Number from Bill, Account Found? (both branches), Account Not Found — Try Again, Manual Search, Manual Match? (both branches), No Match — Contact Support, Property Details Confirmation Screen |
| account-service | `src/modules/account` | Profile Settings, Manage Linked Properties, Notification Preferences, Help & Support / FAQ, History of Objections |
| bill-service | `src/modules/bill` | Home Dashboard, Bills List, Bill Line Items Breakdown, Charges look correct? (both branches), Mark as Correct — Done, Select Disputed Charge(s), Select Dispute Category, View AI-Generated Expected Amount, View Adjusted Bill / Credit |
| objection-service | `src/modules/objection` | Duplicate / Other Charge, Wrong Meter Reading, Incorrect Tariff Classification, Property Not Occupied, Upload Supporting Documents, Sufficient evidence? (both branches), Prompt — Add More Evidence, Review Summary of Objection, Confirm Submission? (both branches), Edit / Go Back, Submit Objection, Submission Successful? (both branches), Error — Retry or Save Draft, Reference Number Issued, Track Objection Status, Status? (all four branches), Under Review by Municipality, More Info Requested, Upload Requested Docs, Objection Rejected, Escalate or Appeal — Call Support, Objection Upheld |
| notification-service | `src/modules/notification` | Confirmation + Email / SMS, Notification Sent to User, Notification Inbox |
| municipality-service | `src/modules/municipality` | No Flutter screens — inbound CRM webhook (ingests municipal resolution, sets ObjectionStatus, triggers notification) |
| queue-consumer | `src/modules/queue-consumer` | No Flutter screens — background worker only |

---

## Flow-Trace Table

> **Key:** Sync = Flutter shows spinner and blocks. Async = Flutter receives 202 or a push notification drives the transition; no spinner blocks the user. client-only = no network call; Flutter navigates locally.

| Flow | Screen Transition | Service | Node.js Module | Endpoint Placeholder | Sync/Async | Flutter Widget |
| --- | --- | --- | --- | --- | --- | --- |
| ONBOARDING | App Launch — Token Check → validate stored JWT | auth-service | `src/modules/auth` | `GET /auth/session` | Sync | app lifecycle / `initState` |
| ONBOARDING | Splash Screen → Welcome / Value Prop (auto-advance 1.5 s) | client-only | — | — | — | auto-advance |
| ONBOARDING | Welcome / Value Prop → Log In | client-only | — | — | — | `ElevatedButton` "Log In" |
| ONBOARDING | Welcome / Value Prop → Sign Up | client-only | — | — | — | `ElevatedButton` "Sign Up" |
| ONBOARDING | Log In form submit → Verify Login OTP | auth-service | `src/modules/auth` | `POST /auth/login` | Sync (202; OTP dispatch async) | `ElevatedButton` "Log In" |
| ONBOARDING | Verify Login OTP submit → Home Dashboard | otp-service | `src/modules/otp` | `POST /otp/verify` (LOGIN → token pair) | Sync | `ElevatedButton` "Verify" |
| ONBOARDING | Sign Up form submit → OTP Sent (registration) | auth-service | `src/modules/auth` | `POST /auth/register/start` | Sync (202; OTP dispatch async) | `ElevatedButton` "Sign Up" |
| ONBOARDING | OTP Sent (registration) → Verify Phone OTP (auto-advance) | client-only | — | — | — | auto-advance |
| ONBOARDING | Verify Phone OTP submit → OTP Valid? | otp-service | `src/modules/otp` | `POST /otp/verify` (REGISTRATION → registrationToken) | Sync | `ElevatedButton` "Verify" |
| ONBOARDING | OTP Valid? — Valid branch → Upload Proof of Address | auth-service | `src/modules/auth` | `POST /auth/register` (creates user, issues tokens) | Sync | routing → register call |
| ONBOARDING | OTP Valid? — Invalid branch → OTP Expired / Resend | client-only | — | — | — | routing (no widget) |
| ONBOARDING | OTP Expired / Resend — "Resend OTP" tap → Verify Phone OTP | otp-service | `src/modules/otp` | `POST /otp/resend` | Sync (202; delivery async) | `TextButton` "Resend OTP" |
| ONBOARDING | Upload Proof of Address submit → Awaiting KYC Approval | auth-service | `src/modules/auth` | `POST /auth/kyc` | Sync | `ElevatedButton` "Submit" |
| ONBOARDING | Awaiting KYC Approval → Home Dashboard (push: kyc_approved) | notification-service | `src/modules/notification` | push notification (`kyc_approved`) | **Async** | push notification handler |
| ONBOARDING | Awaiting KYC Approval → KYC Rejected (push: kyc_rejected) | notification-service | `src/modules/notification` | push notification (`kyc_rejected`) | **Async** | push notification handler |
| ONBOARDING | KYC Rejected → Contact support (terminal) | client-only | — | — | — | `TextButton` "Contact support" |
| ONBOARDING | Home Dashboard load — bills summary | bill-service | `src/modules/bill` | `GET /bills/summary` | Sync | `initState` |
| FIND PROPERTY | Enter Account Number from Bill submit → Account Found? | property-service | `src/modules/property` | `POST /property/search/account` | Sync | `ElevatedButton` "Search" |
| FIND PROPERTY | Account Found? — Found branch → Property Details Confirmation | client-only | — | — | — | routing (no widget) |
| FIND PROPERTY | Account Found? — Not Found branch → Account Not Found — Try Again | client-only | — | — | — | routing (no widget) |
| FIND PROPERTY | Account Not Found — Try Again → Enter Account Number from Bill | client-only | — | — | — | `ElevatedButton` "Try again" |
| FIND PROPERTY | Account Not Found — Try Again → Manual Search | client-only | — | — | — | `TextButton` "Search by address or ERF" |
| FIND PROPERTY | Manual Search submit → Manual Match? | property-service | `src/modules/property` | `POST /property/search/address` | Sync | `ElevatedButton` "Search" |
| FIND PROPERTY | Manual Match? — Match branch → Property Details Confirmation | client-only | — | — | — | routing (no widget) |
| FIND PROPERTY | Manual Match? — No Match branch → No Match — Contact Support | client-only | — | — | — | routing (no widget) |
| FIND PROPERTY | No Match — Contact Support → external (terminal) | client-only | — | — | — | `TextButton` "Contact support" |
| FIND PROPERTY | Property Details Confirmation load | property-service | `src/modules/property` | `GET /property/:id` | Sync | `initState` |
| FIND PROPERTY | Property Details Confirmation "Save" → link property | property-service | `src/modules/property` | `POST /property/link` | Sync | `ElevatedButton` "Save" |
| FIND PROPERTY | Property Details Confirmation "Download PDF" | property-service | `src/modules/property` | `GET /property/:id/pdf` | Sync | `TextButton` "Download PDF" |
| BILL REVIEW | Bills List load | bill-service | `src/modules/bill` | `GET /bills` | Sync | `initState` |
| BILL REVIEW | Bill row tap → Bill Line Items Breakdown load | bill-service | `src/modules/bill` | `GET /bills/:id/lines` | Sync | `ListTile` tap |
| BILL REVIEW | Charges look correct? — Correct branch → Mark as Correct — Done | client-only | — | — | — | routing (no widget) |
| BILL REVIEW | Charges look correct? — Dispute branch → Select Disputed Charge(s) | client-only | — | — | — | routing (no widget) |
| BILL REVIEW | Mark as Correct — Done → record outcome | bill-service | `src/modules/bill` | `POST /bills/:id/review` | Sync | `ElevatedButton` "Mark as correct" |
| BILL REVIEW | Select Disputed Charge(s) → Select Dispute Category | client-only | — | — | — | `ElevatedButton` "Next" |
| BILL REVIEW | Select Dispute Category → Duplicate / Other Charge | client-only | — | — | — | `ListTile` tap |
| BILL REVIEW | Select Dispute Category → Wrong Meter Reading | client-only | — | — | — | `ListTile` tap |
| BILL REVIEW | Select Dispute Category → Incorrect Tariff Classification | client-only | — | — | — | `ListTile` tap |
| BILL REVIEW | Select Dispute Category → Property Not Occupied | client-only | — | — | — | `ListTile` tap |
| BILL REVIEW | Duplicate / Other Charge → create objection draft | objection-service | `src/modules/objection` | `POST /objections/draft` | Sync | `ElevatedButton` "Next" (Duplicate / Other) |
| BILL REVIEW | Wrong Meter Reading → create objection draft | objection-service | `src/modules/objection` | `POST /objections/draft` | Sync | `ElevatedButton` "Next" (Wrong Meter Reading) |
| BILL REVIEW | Incorrect Tariff Classification → create objection draft | objection-service | `src/modules/objection` | `POST /objections/draft` | Sync | `ElevatedButton` "Next" (Incorrect Tariff) |
| BILL REVIEW | Property Not Occupied → create objection draft | objection-service | `src/modules/objection` | `POST /objections/draft` | Sync | `ElevatedButton` "Next" (Property Not Occupied) |
| EVIDENCE & CHALLENGE | View AI-Generated Expected Amount load | bill-service | `src/modules/bill` | `GET /bills/:id/ai-estimate` | Sync (15 s timeout → fallback) | `initState` |
| EVIDENCE & CHALLENGE | Upload Supporting Documents submit → Sufficient evidence? | objection-service | `src/modules/objection` | `POST /objections/:id/evidence` | Sync | `ElevatedButton` "Check evidence" |
| EVIDENCE & CHALLENGE | Sufficient evidence? — Sufficient branch → Review Summary | client-only | — | — | — | routing (no widget) |
| EVIDENCE & CHALLENGE | Sufficient evidence? — Insufficient branch → Prompt — Add More Evidence | client-only | — | — | — | routing (no widget) |
| EVIDENCE & CHALLENGE | Prompt — Add More Evidence → Upload Supporting Documents | client-only | — | — | — | `ElevatedButton` "Add more evidence" |
| EVIDENCE & CHALLENGE | Review Summary of Objection load | objection-service | `src/modules/objection` | `GET /objections/:id/summary` | Sync | `initState` |
| EVIDENCE & CHALLENGE | Confirm Submission? — Edit branch → Upload Supporting Documents | client-only | — | — | — | routing (no widget) |
| EVIDENCE & CHALLENGE | Confirm Submission? — Confirm branch → Submit Objection | client-only | — | — | — | routing (no widget) |
| EVIDENCE & CHALLENGE | Edit / Go Back → Upload Supporting Documents | client-only | — | — | — | back navigation / `TextButton` "Edit" |
| SUBMISSION | Submit Objection → Submission Successful? | objection-service | `src/modules/objection` | `POST /objections/:id/submit` | Sync (30 s timeout) | auto (screen entry event) |
| SUBMISSION | Submission Successful? — Failed branch → Error — Retry or Save Draft | client-only | — | — | — | routing (no widget) |
| SUBMISSION | Submission Successful? — Success branch → Reference Number Issued | client-only | — | — | — | routing (no widget) |
| SUBMISSION | Error — Retry or Save Draft — "Try again" → Submit Objection | objection-service | `src/modules/objection` | `POST /objections/:id/submit` | Sync | `ElevatedButton` "Try again" |
| SUBMISSION | Error — Retry or Save Draft — "Save and try later" → Home Dashboard | client-only | — | — | — | `TextButton` "Save and try later" |
| SUBMISSION | Reference Number Issued → Confirmation + Email/SMS (auto-advance) | client-only | — | — | — | auto-advance |
| SUBMISSION | Confirmation + Email/SMS — email + SMS dispatched | notification-service | `src/modules/notification` | queue task `notification.objection_submitted` | **Async** | push / email / SMS delivery |
| SUBMISSION | Confirmation + Email/SMS → Track Objection Status | client-only | — | — | — | `ElevatedButton` "Track my objection" |
| SUBMISSION | Confirmation + Email/SMS → Home Dashboard | client-only | — | — | — | `TextButton` "Back to Home" |
| TRACKING & RESOLUTION | Track Objection Status load | objection-service | `src/modules/objection` | `GET /objections/:ref/status` | Sync | `initState` |
| TRACKING & RESOLUTION | Status? — Pending branch → Under Review by Municipality | client-only | — | — | — | routing (no widget) |
| TRACKING & RESOLUTION | Status? — More Info branch → More Info Requested | client-only | — | — | — | routing (no widget) |
| TRACKING & RESOLUTION | Status? — Upheld branch → Objection Upheld | client-only | — | — | — | routing (no widget) |
| TRACKING & RESOLUTION | Status? — Rejected branch → Objection Rejected | client-only | — | — | — | routing (no widget) |
| TRACKING & RESOLUTION | Under Review by Municipality — push notification → re-poll Status? | objection-service | `src/modules/objection` | `GET /objections/:ref/status` | **Async** (push triggers sync re-fetch) | push notification handler |
| TRACKING & RESOLUTION | Under Review by Municipality — probe tap | objection-service | `src/modules/objection` | `POST /objections/:ref/probe` | Sync | `ElevatedButton` "Request status update" |
| TRACKING & RESOLUTION | Under Review — 3rd probe → auto-escalation notification | notification-service | `src/modules/notification` | queue task `notification.probe_escalation` | **Async** | background job |
| TRACKING & RESOLUTION | Notification Sent to User → Status? loop (auto-advance) | client-only | — | — | — | auto-advance |
| TRACKING & RESOLUTION | More Info Requested — notification arrival | notification-service | `src/modules/notification` | queue task `notification.objection_status_change` | **Async** | push notification handler |
| TRACKING & RESOLUTION | More Info Requested → Upload Requested Docs | client-only | — | — | — | `ElevatedButton` "Upload documents" |
| TRACKING & RESOLUTION | Upload Requested Docs submit → status transition (`more_info_requested → under_review`, intramodule) | objection-service | `src/modules/objection` | `POST /objections/:id/evidence` | Sync | `ElevatedButton` "Submit documents" |
| TRACKING & RESOLUTION | Objection Rejected — notification arrival | notification-service | `src/modules/notification` | queue task `notification.objection_status_change` | **Async** | push notification handler |
| TRACKING & RESOLUTION | Objection Rejected → Escalate or Appeal — Call Support | client-only | — | — | — | `ElevatedButton` "Appeal formally" |
| TRACKING & RESOLUTION | Escalate or Appeal — Call Support submit | objection-service | `src/modules/objection` | `POST /objections/:ref/escalate` | Sync | `ElevatedButton` "Escalate" |
| TRACKING & RESOLUTION | Objection Upheld — notification arrival | notification-service | `src/modules/notification` | queue task `notification.objection_status_change` | **Async** | push notification handler |
| TRACKING & RESOLUTION | Objection Upheld → View Adjusted Bill / Credit | client-only | — | — | — | `ElevatedButton` "View adjusted bill" |
| TRACKING & RESOLUTION | View Adjusted Bill / Credit load | bill-service | `src/modules/bill` | `GET /bills/:id` (re-fetched post-upheld) | Sync | `initState` |
| TRACKING & RESOLUTION | View Adjusted Bill / Credit — "Close case" | objection-service | `src/modules/objection` | `POST /objections/:ref/close` | Sync | `ElevatedButton` "Close case" |
| ACCOUNT & SETTINGS | Profile Settings load | account-service | `src/modules/account` | `GET /account/profile` | Sync | `initState` |
| ACCOUNT & SETTINGS | Manage Linked Properties load | account-service | `src/modules/account` | `GET /account/properties` | Sync | `initState` |
| ACCOUNT & SETTINGS | Manage Linked Properties — Remove property | account-service | `src/modules/account` | `DELETE /account/properties/:id` | Sync | `IconButton` remove |
| ACCOUNT & SETTINGS | Notification Preferences load | account-service | `src/modules/account` | `GET /account/preferences` | Sync | `initState` |
| ACCOUNT & SETTINGS | Notification Preferences save | account-service | `src/modules/account` | `PUT /account/preferences` | Sync | `ElevatedButton` "Save" |
| ACCOUNT & SETTINGS | History of Objections load | account-service | `src/modules/account` | `GET /account/objections` | Sync | `initState` |
| ACCOUNT & SETTINGS | Help & Support / FAQ — static content load (MVP) | client-only | — | — | — | `initState` (static) |
| ACCOUNT & SETTINGS | Log Out — "Cancel" → stays on screen | client-only | — | — | — | `TextButton` "Cancel" |
| ACCOUNT & SETTINGS | Log Out confirm → clear token | auth-service | `src/modules/auth` | `POST /auth/logout` | Sync | `ElevatedButton` "Log out" |

---

## Cross-Service Synchronous Calls

These are the only two places where one Node.js module calls another as a function during a request. All other cross-module communication is asynchronous via queue-consumer.

| Caller | Callee | Endpoint/Function | Data Passed | Why It Cannot Be Async |
| --- | --- | --- | --- | --- |
| `auth-service` | `otp-service` | `otp.verifyOtp(phone, code)` | `{ phone: string, code: string }` | Login and registration phone verification cannot issue a result (session token pair / registrationToken) until the OTP is confirmed valid. The transaction gate is the verification answer. |
| `objection-service` | `bill-service` | `bill.getCharge(chargeId)` | `{ charge_id: string, bill_id: string }` | An objection draft cannot be created without the charge label, amount, and billing period from bill-service. The draft record requires that data at insert time. |

> The former third row (`objection-service` → `status-service` status transition) is **no longer a cross-service call** — status-service was dissolved, so the `more_info_requested → under_review` transition on document upload is now intramodule within objection-service.

---

## Async Queue Seeds — plan/03 input

> Every row below is an async transition from the flow-trace table. **Copy these rows verbatim into plan/03's LIST task.** No async transition here may be absent from queue-topology.md.

| Queue Task Name | Triggering Service | Consuming Service | Trigger Event | Payload Shape |
| --- | --- | --- | --- | --- |
| `otp.dispatch` | `auth-service` | `otp-service` | `register/start` (registration); `login` (login); OTP resend request | `{ phone, otp_purpose: 'REGISTRATION' \| 'LOGIN', code, expires_at }` |
| `notification.kyc_status_change` | `auth-service` (KYC file-drop ingestion) | `notification-service` | `kyc_status` transitions to `kyc_approved` or `kyc_rejected` | `{ user_id, status: 'kyc_approved' \| 'kyc_rejected', rejection_reason?: string, push_token }` |
| `notification.objection_submitted` | `objection-service` | `notification-service` | `Objection.status` transitions `draft → submitted` | `{ user_id, reference_number, email, phone, disputed_items_summary: string }` |
| `notification.objection_status_change` | `municipality-service` | `notification-service` | inbound CRM webhook sets `Objection.status` to `more_info_requested`, `upheld`, or `rejected` | `{ user_id, reference_number, new_status, email, phone, push_token, deep_link_path }` |
| `notification.probe_escalation` | `objection-service` | `notification-service` | 3rd probe submitted on a single objection | `{ user_id, reference_number, probe_count: 3, push_token }` |

---

## Hop-Count Table

> A "synchronous hop" is one Flutter → backend call, or one synchronous cross-service function call within the backend. Happy path only. Flows with more than two synchronous hops are flagged.

| Flow | Synchronous Hops | Services Crossed | Hop Detail |
| --- | --- | --- | --- |
| ONBOARDING — Log In (passwordless) | 2 | auth, otp | Flutter → auth (login, dispatch LOGIN OTP) → otp.verifyOtp (Verify Login OTP, issues tokens) |
| ONBOARDING — Sign Up + Register | 3 | auth, otp | Flutter → auth (register/start, dispatch REGISTRATION OTP) → otp.verifyOtp (registrationToken) → auth (register, creates user + issues tokens) |
| FIND PROPERTY — Account Number search | 1 | property | Flutter → property |
| BILL REVIEW — View Bill + Dispute | 2 | bill, objection | Flutter → bill (load lines) → objection (create draft) |
| EVIDENCE & CHALLENGE — Submit Objection | 2 | objection, bill | Flutter → objection (submit) → bill.getCharge (internal, at draft creation) |
| TRACKING & RESOLUTION — Upload Requested Docs | 1 | objection | Flutter → objection (upload evidence; `more_info_requested → under_review` transition is intramodule) |

**ONBOARDING — Sign Up + Register** is the only flow exceeding two synchronous hops (3) — an
accepted consequence of OTP-first registration (ADR-002): the phone is verified *before* the
`User` is created, so `register/start → otp.verify → register` is an irreducible three-step
sequence. All other flows remain within two hops.
