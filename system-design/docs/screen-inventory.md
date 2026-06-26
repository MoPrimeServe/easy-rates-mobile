# EasyRates Mobile App — Screen Inventory

**Source:** Process Flows.pdf — all seven customer-facing flows  
**Rules:**
- Every pink diamond produces two rows (one per branch)
- Every error state has its own row
- Every terminal / success state has its own row
- **User-Facing Data Fields** lists exactly what a Flutter widget must display or accept — this column is the source for request/response schema design (plan/09)
- Service Owner confirmed per `easy_rates/system-design/docs/service-map.md`

---

## ONBOARDING

| Flow | Screen Name | States | User-Facing Data Fields | Triggering Event | Outgoing Transitions | Service Owner | Notes |
|---|---|---|---|---|---|---|---|
| ONBOARDING | App Launch — Token Check | `checking` | None — invisible routing step | App opens | Valid token → Home Dashboard; No token → Splash Screen | auth-service | Auto-detects stored JWT. If valid: skip all onboarding. Splash Screen only shown to unauthenticated users. |
| ONBOARDING | Splash Screen | `visible` | App logo, tagline | No valid token found | → Welcome / Value Prop (auto-advance, max 1.5 s) | — | Branding only. No API call. |
| ONBOARDING | Welcome / Value Prop | `idle` | App name, value proposition copy, "Log In" CTA, "Sign Up" CTA | Splash completes | "Log In" → Log In; "Sign Up" → Sign Up | — | Static screen. No API call. |
| ONBOARDING | Log In | `idle` \| `submitting` \| `error` | INPUT: phone number (mask: +27 XX XXX XXXX); DISPLAY: instruction copy, error message | User selects "Log In" from Welcome | OTP dispatched (if registered) → Verify Login OTP | auth-service + otp-service | Passwordless (ADR-002). `POST /auth/login` is anti-enumeration — always advances to OTP entry; no password, no "Forgot password?", no account lock. |
| ONBOARDING | ~~Forgot Password~~ (removed) | — | — | — | — | — | **Removed (ADR-002)** — passwordless; nothing to reset. A locked-out user just logs in again (fresh LOGIN OTP). |
| ONBOARDING | Verify Login OTP | `idle` \| `submitting` \| `error` \| `expired` | INPUT: OTP code (6-digit numeric); DISPLAY: masked phone number, countdown timer, "Resend" link (enabled after 30 s), error message | Log In submitted (LOGIN OTP) | Valid OTP → `otp/verify` issues token pair → Home Dashboard; Expired → OTP Expired / Resend | otp-service | Countdown from 10 min. Resend cooldown 30 s, max 3 resends. **Login token pair issued here** (ADR-002). |
| ONBOARDING | ~~Reset via OTP — Set New Password~~ (removed) | — | — | — | — | — | **Removed (ADR-002)** — no password to set. |
| ONBOARDING | Sign Up | `idle` \| `submitting` \| `error` | INPUT: full name (text), email (email), SA ID number (13-digit numeric), cell phone number (+27 format), proof of address (file upload — PDF / JPEG / PNG, max 10 MB); DISPLAY: field validation errors, upload progress indicator | "Sign Up" selected from Welcome | `POST /auth/register/start` → OTP Sent (registration) → Verify Phone OTP | auth-service + otp-service | Passwordless, OTP-first (ADR-002): no password field. `register/start` checks phone uniqueness + dispatches REGISTRATION OTP; the `User` is created later by `POST /auth/register` (after OTP), which issues tokens. SA ID required + Luhn-validated. |
| ONBOARDING | OTP Sent (registration) | `visible` | DISPLAY: masked phone number ("OTP sent to +27 XX XXX X234"), expiry note | `register/start` success | Auto-advance → Verify Phone OTP | otp-service | Interstitial. No user input. REGISTRATION OTP dispatched. **Account not yet created** — creation happens after OTP at `POST /auth/register` (ADR-002). |
| ONBOARDING | Verify Phone OTP | `idle` \| `submitting` \| `error` | INPUT: OTP code (6-digit numeric); DISPLAY: masked phone, countdown timer (10 min), "Resend" link (enabled after 30 s, max 3), attempt counter, error message | OTP Sent (registration) | OTP Valid? diamond | otp-service | Valid → `otp/verify` returns `registrationToken` → client calls `POST /auth/register` (creates user, issues tokens) → Upload Proof of Address (ADR-002). |
| ONBOARDING | OTP Valid? — Valid branch | — | — | OTP submitted and verified | → Upload Proof of Address | otp-service | Routing decision. No screen rendered. |
| ONBOARDING | OTP Valid? — Invalid branch | — | — | OTP submitted and rejected | → OTP Expired / Resend | otp-service | Covers both wrong-code and expired-code outcomes. |
| ONBOARDING | OTP Expired / Resend | `idle` \| `resending` | DISPLAY: "Your OTP has expired or is invalid" message; CTA: "Resend OTP"; DISPLAY: resend attempt counter ("X of 3 resends used") | OTP Valid? → Invalid | Resend tapped → Verify Phone OTP (new OTP dispatched) | otp-service | After 3 resends: show support contact CTA instead of Resend. |
| ONBOARDING | Upload Proof of Address | `idle` \| `uploading` \| `uploaded` \| `error` | INPUT: file upload widget (PDF / JPEG / PNG, max 10 MB); DISPLAY: accepted format list, upload progress bar, uploaded file name with remove option, submit CTA | OTP Valid? → Valid | Uploaded + submitted → Awaiting KYC Approval | auth-service | Sets `kyc_status = kyc_pending`. Triggers simulated municipality review queue. |
| ONBOARDING | Awaiting KYC Approval | `waiting` | DISPLAY: "Your proof of address is being reviewed" message, reference to uploaded document, "This usually takes up to 1 week" copy | Upload Proof of Address submitted | Municipality approval (push notification) → Home Dashboard; Municipality rejection (push notification) → KYC Rejected | auth-service | Full gate — no app features accessible. Push notification drives exit from this screen. |
| ONBOARDING | KYC Rejected | `visible` | DISPLAY: rejection reason (verbatim from municipality file drop), "Contact support" CTA, submission reference | Push notification: kyc_rejected | "Contact support" → support channel | auth-service | Terminal for self-serve path. Support resets `kyc_status` externally via file drop. |
| ONBOARDING | Home Dashboard | `loading` \| `loaded` \| `error` | DISPLAY: total outstanding (sum across linked properties), account last-4 digits, account holder name, next due date; NAV: Pay, Bills, Usage, Auto-pay, More | KYC approved (push) OR valid JWT on app open | Bills tab → Bill list; other nav items per ACCOUNT & SETTINGS | bill-service | Entry point for all downstream flows. |

---

## FIND PROPERTY

| Flow | Screen Name | States | User-Facing Data Fields | Triggering Event | Outgoing Transitions | Service Owner | Notes |
|---|---|---|---|---|---|---|---|
| FIND PROPERTY | Enter Account Number from Bill | `idle` \| `searching` \| `error` | INPUT: account number (8-digit numeric, input mask); DISPLAY: validation error, network error | User initiates "Add property" from Account & Settings / Manage Linked Properties | Account Found? diamond | property-service | Pre-condition: `user.kyc_status == kyc_approved`. Format: exactly 8 digits. |
| FIND PROPERTY | Account Found? — Found branch | — | — | Account number submitted and identity check passes | → Property Details Confirmation Screen | property-service | Identity check: `user.id_number` in `property.holder_id_numbers`. Returns generic "not found" if unauthorized. |
| FIND PROPERTY | Account Found? — Not Found branch | — | — | Account number submitted and no match / identity mismatch | → Account Not Found — Try Again | property-service | Deliberately ambiguous — never reveals whether account exists but user is unauthorized. |
| FIND PROPERTY | Account Not Found — Try Again | `visible` | DISPLAY: entered account number (for user reference), "Account not found" message; CTA: "Try again" (re-enter account number), "Search by address or ERF" | Account Found? → Not Found | "Try again" → Enter Account Number from Bill; "Search by address or ERF" → Manual Search | property-service | Two exits: retry same method or escalate to manual search. |
| FIND PROPERTY | Manual Search (Address / ERF) | `idle` \| `searching` \| `error` | INPUT: toggle (Address tab / ERF tab); Address tab: street address (text); ERF tab: ERF number (text); DISPLAY: validation error, network error | "Search by address or ERF" tapped | Manual Match? diamond | property-service | Toggle — one field active at a time. At least one field required. |
| FIND PROPERTY | Manual Match? — Match branch | — | — | Address or ERF submitted and identity check passes | → Property Details Confirmation Screen | property-service | Same identity-gate logic as account number search. |
| FIND PROPERTY | Manual Match? — No Match branch | — | — | Address or ERF submitted and no match / identity mismatch | → No Match — Contact Support | property-service | Terminal error for FIND PROPERTY. |
| FIND PROPERTY | No Match — Contact Support | `visible` | DISPLAY: "We couldn't find this property" message, support contact CTA, instruction to verify account number on bill | Manual Match? → No Match | "Contact support" → support channel | property-service | Terminal. User has exhausted both search methods. |
| FIND PROPERTY | Property Details Confirmation Screen | `loading` \| `loaded` \| `error` | DISPLAY: account number, account holder name(s), physical address, ERF / portion, extent (m²), property value (municipal), `data_as_of` timestamp; CTA: "Save" (link property), "View More" (→ Bill Review), "Download PDF"; DISPLAY: staleness warning if `data_as_of` exceeds threshold | Account Found? → Found OR Manual Match? → Match | "Save" → links property + stays on screen; "View More" → Bill Line Items Breakdown; "Download PDF" → PDF export | property-service | Property linked to user profile on "Save" tap. `data_as_of` shown so user knows freshness. |

---

## BILL REVIEW

| Flow | Screen Name | States | User-Facing Data Fields | Triggering Event | Outgoing Transitions | Service Owner | Notes |
|---|---|---|---|---|---|---|---|
| BILL REVIEW | Bills List | `loading` \| `loaded` \| `empty` \| `error` | DISPLAY: per bill row — icon (charge category), bill name + period (e.g. "Assessment Rates · Q1"), due date, amount (negative/red = owed, positive/green = credit), status chip (due_soon \| overdue \| paid \| disputed \| under_review \| upheld \| rejected \| credit \| draft); "See all" CTA | "Bills" tab tapped on Home Dashboard | Tap bill row → Bill Line Items Breakdown | bill-service | Entry point replaces direct "View Current Bill." Bills grouped by linked property. |
| BILL REVIEW | Bill Line Items Breakdown | `loading` \| `loaded` \| `empty` \| `error` | DISPLAY: account number, account holder, total due, valid from / valid to (quarterly), `data_as_of`; LINE ITEMS: category label, amount, debt type, date valid from, date valid to; anomaly highlight on flagged charges; ADJUSTMENTS: base balance, split labels, balance after adjustment; CTA: "Charges look correct?" decision | Bill row tapped OR "View More" from Property Details | Charges look correct? diamond | bill-service | Anomaly-flagged charges highlighted before user acts. Quarterly billing period. Shows base balance + adjustment splits. |
| BILL REVIEW | Charges look correct? — Correct branch | — | — | User taps "Mark as correct" | → Mark as Correct — Done | bill-service | User action, not backend decision. |
| BILL REVIEW | Charges look correct? — Dispute branch | — | — | User taps "Dispute a charge" | → Select Disputed Charge(s) | bill-service | |
| BILL REVIEW | Mark as Correct — Done | `visible` | DISPLAY: confirmation message "Bill marked as correct"; CTA: stays on Bill Line Items Breakdown | Charges look correct? → Correct | Stays on bill screen | bill-service | Records BillReview outcome = correct. No navigation away. |
| BILL REVIEW | Select Disputed Charge(s) | `idle` \| `error` | DISPLAY: multi-select list of line items — each row: category label, amount, period; DISPLAY: "Select at least one charge" validation; CTA: "Next" | Dispute branch OR direct entry from Property Details "Dispute" shortcut | → Select Dispute Category | bill-service | At least one charge must be selected. Carries `{property_id, bill_id}` if entered via deep shortcut. |
| BILL REVIEW | Select Dispute Category | `idle` | DISPLAY: dynamic list of valid dispute categories for selected charge(s) — Duplicate / Other Charge, Wrong Meter Reading (metered services only), Incorrect Tariff Classification (rated services only), Property Not Occupied; CTA: "Next" | Select Disputed Charge(s) → Next | One category selected → corresponding category entry node for EVIDENCE & CHALLENGE | bill-service | Category options filtered per charge type. Each charge gets its own category. |
| BILL REVIEW | Duplicate / Other Charge | `visible` | DISPLAY: selected charge details, category confirmation | Category selected: duplicate_other | → View AI-Generated Expected Amount (EVIDENCE & CHALLENGE entry) | objection-service | Entry node to EVIDENCE & CHALLENGE. Objection draft created with `{charge_id, category}`. |
| BILL REVIEW | Wrong Meter Reading | `visible` | DISPLAY: selected charge details, category confirmation | Category selected: wrong_meter_reading | → View AI-Generated Expected Amount (EVIDENCE & CHALLENGE entry) | objection-service | Entry node to EVIDENCE & CHALLENGE. |
| BILL REVIEW | Incorrect Tariff Classification | `visible` | DISPLAY: selected charge details, category confirmation | Category selected: incorrect_tariff | → View AI-Generated Expected Amount (EVIDENCE & CHALLENGE entry) | objection-service | Entry node to EVIDENCE & CHALLENGE. |
| BILL REVIEW | Property Not Occupied | `visible` | DISPLAY: selected charge details, category confirmation | Category selected: property_not_occupied | → View AI-Generated Expected Amount (EVIDENCE & CHALLENGE entry) | objection-service | Entry node to EVIDENCE & CHALLENGE. |

---

## EVIDENCE & CHALLENGE

| Flow | Screen Name | States | User-Facing Data Fields | Triggering Event | Outgoing Transitions | Service Owner | Notes |
|---|---|---|---|---|---|---|---|
| EVIDENCE & CHALLENGE | View AI-Generated Expected Amount | `loading` \| `loaded` \| `unavailable` \| `error` | DISPLAY: disputed charge label, charged amount, AI-calculated expected amount (hidden if confidence < 0.85), difference (overcharge), confidence indicator (Low / Medium / High), basis summary ("Based on average Q1 usage for your property type in Vereeniging"); fallback: "Insufficient data to calculate expected amount. You may still submit your objection."; CTA: "Continue to upload evidence" | Any of four category entry nodes | → Upload Supporting Documents | bill-service (AI) | AI model: Ollama on local RTX 4070. Synchronous call. 15 s timeout → show fallback. `model_version` stored. Confidence threshold: 0.85. |
| EVIDENCE & CHALLENGE | Upload Supporting Documents | `idle` \| `uploading` \| `uploaded` \| `error` | INPUT: multi-file upload widget (PDF / JPEG / PNG, max 10 MB per file, max 5 files per objection); DISPLAY: required document type hints (per dispute category), uploaded files list (each with file name, size, remove button), upload progress bar; CTA: "Check evidence" | View AI-Generated Expected Amount → Continue OR Prompt — Add More Evidence loop | → Sufficient evidence? diamond | objection-service | Required doc types per category: Wrong Meter Reading → meter photo / previous reading; Incorrect Tariff → zoning cert / property deed; Property Not Occupied → vacancy affidavit; Duplicate/Other → any document. |
| EVIDENCE & CHALLENGE | Sufficient evidence? — Sufficient branch | — | — | Evidence check passes (backend rule engine) | → Review Summary of Objection | objection-service | Rule-based for MVP: document count + type per category. AI content verification post-MVP. |
| EVIDENCE & CHALLENGE | Sufficient evidence? — Insufficient branch | — | — | Evidence check fails | → Prompt — Add More Evidence | objection-service | |
| EVIDENCE & CHALLENGE | Prompt — Add More Evidence | `visible` | DISPLAY: submitted files list, "What's missing" copy (from sufficiency check response — required document types per unmet category), "Add more evidence" CTA | Sufficient evidence? → Insufficient | "Add more evidence" → Upload Supporting Documents (loop) | objection-service | No hard cap on retry loops. All previously uploaded docs retained. |
| EVIDENCE & CHALLENGE | Review Summary of Objection | `loading` \| `loaded` | DISPLAY: property (account, address), bill period, disputed items (each: charge label, charged amount, expected amount if shown, dispute category), uploaded documents (file names + types), total disputed amount; CTA: "Confirm submission", "Edit" | Sufficient evidence? → Sufficient | "Confirm" → Confirm Submission? diamond | objection-service | Tapping "Confirm" is sufficient — no checkbox declaration. |
| EVIDENCE & CHALLENGE | Confirm Submission? — Edit branch | — | — | User taps "Edit" | → Upload Supporting Documents | objection-service | Goes back to Upload Supporting Documents only — not all the way to bill selection. |
| EVIDENCE & CHALLENGE | Confirm Submission? — Confirm branch | — | — | User taps "Confirm" | → Submit Objection (SUBMISSION entry) | objection-service | Objection stays in `draft` status until SUBMISSION confirms. |
| EVIDENCE & CHALLENGE | Edit / Go Back | `visible` | DISPLAY: transition screen — no visible content (immediate navigation) | Confirm Submission? → Edit | → Upload Supporting Documents | objection-service | Navigates back to Upload Supporting Documents only. |

---

## SUBMISSION

| Flow | Screen Name | States | User-Facing Data Fields | Triggering Event | Outgoing Transitions | Service Owner | Notes |
|---|---|---|---|---|---|---|---|
| SUBMISSION | Submit Objection | `submitting` \| `error` | DISPLAY: loading indicator, "Submitting your objection…" message | Confirm Submission? → Confirm | → Submission Successful? diamond | objection-service | Action screen only — no user input. API call is the screen event. 30 s timeout. |
| SUBMISSION | Submission Successful? — Failed branch | — | — | API returns `{submitted: false, retryable: true}` | → Error — Retry or Save Draft | objection-service | Transient failures only. Non-retryable validation errors route back to EVIDENCE & CHALLENGE. |
| SUBMISSION | Submission Successful? — Success branch | — | — | API returns `{submitted: true, reference_number}` | → Reference Number Issued | objection-service | `Objection.status` transitions `draft → submitted`. Reference number generated. |
| SUBMISSION | Error — Retry or Save Draft | `visible` | DISPLAY: friendly error message (network / service unavailable — no technical detail), error category ("Network error" / "Service temporarily unavailable"), assurance copy "Your objection has been saved. No information has been lost."; CTA: "Try again" (primary), "Save and try later" (secondary) | Submission Successful? → Failed | "Try again" → Submit Objection (loop); "Save and try later" → Home Dashboard (draft preserved) | objection-service | Draft preserved in full regardless of which exit is taken. Idempotency key: `draft_id`. |
| SUBMISSION | Reference Number Issued | `visible` | DISPLAY: reference number (large, prominent — format ELM-2026-NNNNNN), copy-to-clipboard button, submitted-at timestamp, property address + account number | Submission Successful? → Success | Auto-advance → Confirmation + Email / SMS | objection-service | Reference number is the permanent tracking handle. |
| SUBMISSION | Confirmation + Email / SMS | `visible` | DISPLAY: reference number, "Confirmation sent to [masked email] and [masked phone]", disputed items summary (charge labels + amounts), CTA: "Track my objection" (→ TRACKING & RESOLUTION), "Back to Home" | Reference Number Issued | "Track my objection" → Track Objection Status; "Back to Home" → Home Dashboard | notification-service | Async: email + SMS dispatched by backend on `submitted` status. Deep-link in both channels → Track Objection Status by reference number. |

---

## TRACKING & RESOLUTION

| Flow | Screen Name | States | User-Facing Data Fields | Triggering Event | Outgoing Transitions | Service Owner | Notes |
|---|---|---|---|---|---|---|---|
| TRACKING & RESOLUTION | Track Objection Status | `loading` \| `loaded` \| `error` | DISPLAY: reference number (ELM-2026-NNNNNN), property address + account number, current status chip, status timeline (chronological: each status change with timestamp + notes), disputed items summary, submitted-at, last-updated-at; PROBE: "Request status update" CTA (visible when `status = submitted` AND `submitted_at > 48 h ago`), probe counter "X of 3 probes sent"; CTA: refresh | Confirmation screen "Track my objection" OR notification deep-link by reference number | Status? diamond (re-polled on push notification or manual refresh) | status-service | Persistent anchor screen. Re-fetches status on every push notification and every app resume if status is non-terminal. |
| TRACKING & RESOLUTION | Status? — Pending branch | — | — | `Objection.status == pending` | → Under Review by Municipality | status-service | Municipality acknowledged the submission. |
| TRACKING & RESOLUTION | Status? — More Info branch | — | — | `Objection.status == more_info_requested` | → More Info Requested | status-service | Municipality has requested additional documents. |
| TRACKING & RESOLUTION | Status? — Upheld branch | — | — | `Objection.status == upheld` | → Objection Upheld | status-service | Municipality approved the objection. |
| TRACKING & RESOLUTION | Status? — Rejected branch | — | — | `Objection.status == rejected` | → Objection Rejected | status-service | Municipality denied the objection. |
| TRACKING & RESOLUTION | ⏳ Under Review by Municipality | `visible` | DISPLAY: status message "Your objection is being reviewed", days since submission, expected timeline "Allow up to 1 week", probe CTA ("Request status update") with counter | Status? → Pending | Push notification (status change) → re-polls Status?; Probe tapped → POST probe | status-service | Probe rate-limited: once per 24 h, max 3. After 3rd probe: auto-escalate to support + push notification. |
| TRACKING & RESOLUTION | Notification Sent to User | `visible` | DISPLAY: "We've notified you by email and SMS" confirmation, brief notification content summary | Under Review → notification dispatched | → Status? (loop) | notification-service | Confirms the push / email / SMS was sent. Auto-advances back to status poll loop. |
| TRACKING & RESOLUTION | 🔁 More Info Requested | `visible` | DISPLAY: municipality's request text (verbatim), required document types (list), deadline (if provided by municipality), original disputed items for context; CTA: "Upload documents" | Status? → More Info; Push notification deep-link | → Upload Requested Docs | status-service | Push notification: email + SMS + push. Deep-link directly here. |
| TRACKING & RESOLUTION | Upload Requested Docs | `idle` \| `uploading` \| `uploaded` \| `error` | INPUT: multi-file upload widget (same constraints as EVIDENCE & CHALLENGE: PDF / JPEG / PNG, max 10 MB, max 5 files); DISPLAY: required document types from municipality request, uploaded files list with remove option; CTA: "Submit documents" | More Info Requested → "Upload documents" | Upload success → Track Objection Status; `Objection.status` auto-transitions `more_info_requested → pending` | status-service + objection-service | No re-submit button needed — upload triggers automatic status transition. |
| TRACKING & RESOLUTION | ❌ Objection Rejected | `visible` | DISPLAY: rejection reason (verbatim from municipality), rejected-at timestamp, which charges were rejected (per disputed item); CTA: "Appeal formally", "Call support" | Status? → Rejected; Push notification deep-link | → Escalate or Appeal — Call Support | status-service | Push notification: email + SMS + push. Deep-link directly here. |
| TRACKING & RESOLUTION | Escalate or Appeal — Call Support | `idle` \| `submitting` | DISPLAY: reference number, rejection reason summary, escalation type options (formal appeal / call support), support contact details (phone + hours); CTA: "Escalate" | Objection Rejected → CTA tapped | Escalation submitted → Track Objection Status; `Objection.status` transitions `rejected → escalated` | status-service | Same reference number retained — no new reference issued. |
| TRACKING & RESOLUTION | ✅ Objection Upheld | `visible` | DISPLAY: upheld charges (per disputed item), original charged amount, adjusted amount, credit amount (if overpaid), effective date; CTA: "View adjusted bill" | Status? → Upheld; Push notification deep-link | → View Adjusted Bill / Credit | status-service | Push notification: email + SMS + push. Deep-link directly here. |
| TRACKING & RESOLUTION | View Adjusted Bill / Credit | `loading` \| `loaded` | DISPLAY: original bill total, disputed amount, adjusted total, credit amount (positive/green), effective date, re-fetched bill line items (updated); CTA: "Close case" (→ `credit_applied → closed`), "Contact support if dissatisfied" | Objection Upheld → "View adjusted bill" | "Close case" → Track Objection Status (`status = closed`); "Contact support" → `status = escalated` | bill-service + status-service | Bill re-fetched after upheld to show updated totals. Case fully closed on "Close case" tap. Support CTA available if user is dissatisfied with adjustment. |

---

## ACCOUNT & SETTINGS

| Flow | Screen Name | States | User-Facing Data Fields | Triggering Event | Outgoing Transitions | Service Owner | Notes |
|---|---|---|---|---|---|---|---|
| ACCOUNT & SETTINGS | Profile Settings | `loading` \| `loaded` \| `saving` | DISPLAY: full name, email, masked phone number, masked SA ID number; CTA: edit (read-only for MVP — changes via support) | "More" → "Profile" from Home Dashboard nav | Back to Home Dashboard | account-service | No self-serve field edits for MVP. |
| ACCOUNT & SETTINGS | Manage Linked Properties | `loading` \| `loaded` \| `empty` | DISPLAY: list of linked properties (each: address, account number, ERF, status chip); CTA: "Add property" (→ FIND PROPERTY), remove property | "More" → "Manage properties" | "Add property" → FIND PROPERTY entry; "Remove" → unlinks UserProperty | account-service + property-service | |
| ACCOUNT & SETTINGS | Notification Preferences | `loading` \| `loaded` \| `saving` | DISPLAY: toggle list per notification type (email / SMS always on for MVP — toggle UI deferred to post-MVP); CTA: save | "More" → "Notifications" | Back | account-service | Both email and SMS always sent for MVP. UI scaffold only. |
| ACCOUNT & SETTINGS | History of Objections | `loading` \| `loaded` \| `empty` | DISPLAY: list of all objections — each: reference number, property address, submitted date, status chip, disputed amount; CTA: tap row → Track Objection Status | "More" → "History" | Tap row → Track Objection Status for selected reference | status-service | Read-only list. |
| ACCOUNT & SETTINGS | Notification Inbox | `loading` \| `loaded` \| `empty` | DISPLAY: list of notifications — each: type icon, title, preview, sent date, read/unread chip; CTA: tap row → deep-link destination | "More" → "Notifications inbox" OR push deep-link entry | Tap row → deep-link destination (Track Objection Status / Bill / Home); mark-read on open | notification-service | Backs `GET /notifications` + `POST /notifications/:id/read`. Added per API orphan audit R-1. |
| ACCOUNT & SETTINGS | Help & Support / FAQ | `loading` \| `loaded` | DISPLAY: FAQ content, "Contact support" CTA, support phone + email | "More" → "Help" | "Contact support" → external channel | account-service | Static content for MVP. |
| ACCOUNT & SETTINGS | Log Out | `confirming` | DISPLAY: confirmation dialog "Are you sure you want to log out?"; CTA: "Log out" (confirm), "Cancel" | "More" → "Log out" | Confirmed → App Launch (token cleared); Cancelled → stays | auth-service | Clears JWT + refresh token from device storage. |

---

## Summary counts

| Flow | Screens | Pink Diamonds | Error / Warning States | Terminal / Success States |
|---|---|---|---|---|
| Onboarding | 14 | 2 (OTP Valid?, Token Check) | OTP Expired/Resend, KYC Rejected, Log In error, Sign Up error | Home Dashboard |
| Find Property | 9 | 2 (Account Found?, Manual Match?) | Account Not Found — Try Again, No Match — Contact Support | Property Details Confirmation Screen |
| Bill Review | 10 | 1 (Charges look correct?) | — | Mark as Correct — Done |
| Evidence & Challenge | 9 | 2 (Sufficient evidence?, Confirm Submission?) | Prompt — Add More Evidence | — |
| Submission | 5 | 1 (Submission Successful?) | Error — Retry or Save Draft | Reference Number Issued, Confirmation + Email/SMS |
| Tracking & Resolution | 14 | 1 (Status? × 4 branches) | ❌ Objection Rejected | ✅ View Adjusted Bill / Credit (closed) |
| Account & Settings | 7 | — | — | — |
| **Total** | **68** | **9 diamonds / 17 branch rows** | | |

---

## Notification deep-link map

| Status transition | Notification channels | Deep-link destination screen |
|---|---|---|
| `kyc_pending → kyc_approved` | Push | Home Dashboard |
| `kyc_pending → kyc_rejected` | Push | KYC Rejected |
| `draft → submitted` (confirmation) | Email + SMS | Confirmation + Email/SMS |
| `pending → more_info_requested` | Email + SMS + Push | 🔁 More Info Requested |
| `pending → rejected` | Email + SMS + Push | ❌ Objection Rejected |
| `pending → upheld` | Email + SMS + Push | ✅ Objection Upheld |
| Probe auto-escalation (3rd probe) | Push | Track Objection Status |

---

## Dispute category validity matrix

| Charge category | Duplicate / Other | Wrong Meter Reading | Incorrect Tariff | Property Not Occupied |
|---|---|---|---|---|
| Assessment Rates | ✓ | — | ✓ | ✓ |
| Refuse removal | ✓ | — | ✓ | ✓ |
| Sewerage | ✓ | ✓ | — | ✓ |
| Basic Electricity | ✓ | ✓ | ✓ | ✓ |
| Basic Water | ✓ | ✓ | ✓ | ✓ |
| Water consumption | ✓ | ✓ | ✓ | ✓ |
| Arrears | ✓ | — | — | — |
| Admin fee | ✓ | — | — | — |
| Interest | ✓ | — | — | — |
| Prior period outstanding balance | ✓ | — | — | — |
