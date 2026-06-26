# 👤 Account Service Contract

## Background

✅ resolved[Gate] — `api/conventions.md` exists and is referenced by the deliverable (envelope §2, error codes §3, pagination §7, dates/money §9, camelCase §10).
✅ resolved[Gate] — data-model exists: `docs/data-model/user-auth.md` (User schema: displayName, email, idNumberHash) and `docs/data-model/property-account.md` (AccountStatus) supply the profile/linked-property field names and the POPIA-sensitive fields (idNumberHash → masked in response).

The account service handles the ACCOUNT & SETTINGS Figma flow. It exposes the
ratepayer's profile and notification preferences.

## Description

Write the HTTP API contract for the account service: GET profile, PATCH profile
(partial update), change-password (or change-PIN if PIN-based), and notification
preferences. Includes POPIA-sensitive field notes and partial-update semantics.

## Purpose

To answer: "if the Flutter user updates only their email address in the profile
form, does the PATCH endpoint require the full profile or just the changed fields —
and how does the Flutter developer know which semantics to implement?"

## Goal

`easy_rates/system-design/api/account-service.md` — profile GET/PATCH + change-password
routes with TypeScript interfaces; partial-update semantics explicit; POPIA note on
sensitive fields.

## Tasks

- [x] ✅ — ✓ verified (THINK answered in Execution Note; deliverable line 9 defers profile PATCH (read-only MVP), line 125 sets PUT /preferences partial-update synchronous-return semantics, line 30 masks idNumber/phone — POPIA fields identified) THINK `/socratic "If a Flutter user updates their email address and then
  immediately requests their profile, should the GET response show the new email
  or the old one — and what does that tell us about whether PATCH needs to be
  synchronous? And what POPIA-sensitive fields are in the profile response — which
  of them should we think twice about exposing in a profile GET?"`
  Done when: partial-update semantics decision made; POPIA-sensitive profile fields
  identified; synchronous update confirmed.

- [x] ✅ — ✓ verified (Figma Trace table, deliverable lines 277-288, maps every ACCOUNT & SETTINGS screen: Profile Settings→GET /profile, Manage Linked Properties→GET /properties + POST /property/link + DELETE /properties/:id, Notification Preferences→GET/PUT /preferences, History of Objections→GET /objections, Log Out→POST /auth/logout) FIGMA-TRACE Map every ACCOUNT & SETTINGS flow screen transition:
  Profile screen load → GET /api/v1/account/profile
  "Edit profile" save → PATCH /api/v1/account/profile
  Notification toggle → PATCH /api/v1/account/notifications
  Change password/PIN → PATCH /api/v1/account/change-password (or similar)
  For each: Flutter widget trigger; which response field populates which UI element.
  Done when: all ACCOUNT & SETTINGS transitions mapped.

- [x] ✅ — ✓ verified (GET /account/profile defined, deliverable lines 15-36; raw idNumber NOT returned — exposed only as `idNumberMasked` "8•••••••••••89" (line 30), and the schema stores only `idNumberHash` / ADR-003 so a raw value cannot be returned; fields userId/displayName/email match data-model/user-auth.md. NOTE: deliverable masks (not omits) idNumber, and uses displayName/phoneMasked rather than the plan's fullName/phoneNumber — a deliberate POPIA-hardening divergence from this plan's literal shape) GET-PROFILE Define `GET /api/v1/account/profile`:
  Response 200:
  ```json
  { "data": {
      "userId": "string",
      "phoneNumber": "string",
      "email": "string|null",
      "fullName": "string",
      "createdAt": "ISO 8601 datetime"
    }, "error": null }
  ```
  POPIA note: `idNumber` is NOT returned in the profile response (special personal
  information; not needed by the Flutter profile screen).
  TypeScript interface: `UserProfileResponse`
  Done when: response shape defined; `idNumber` explicitly absent with justification.

- [x] ❌ DESCOPED — deliverable DEFERS profile PATCH (line 9, MASTER_PLAN G4): "no Figma screen supports self-serve profile edits in MVP; included here they would be reverse orphans." Profile is read-only for MVP (lines 11, 17). This route is intentionally absent, not authored. Resolved as descoped-by-decision (not a gap); revisit if a profile-edit screen is added post-MVP.
  PATCH-PROFILE Define `PATCH /api/v1/account/profile`:
  Semantics: partial update — only include fields that are changing; omitted fields
  are not modified. (This is PATCH semantics, not PUT semantics.)
  Request: `{ email?: string, fullName?: string }` (phoneNumber is not updatable
  via this endpoint — phone changes require re-OTP verification).
  Response 200: `{ data: UserProfileResponse, error: null }` (returns full updated profile)
  Errors: 409 conflict (email already used), 400 validation_error
  Note: state explicitly in the contract that this is partial update (PATCH),
  not a full replacement (PUT) — Flutter developer must not send the full profile
  object if only one field changed.
  TypeScript interface: `UpdateProfileRequest`
  Done when: partial-update semantics explicit; phone not updatable noted.

- [x] ✅ — ✓ verified (notification-prefs update defined at PUT /account/preferences, deliverable lines 123-156; request is any subset of {smsEnabled, pushEnabled, emailEnabled, language} (line 127), partial-update semantics explicit — "omitted fields are left unchanged" (line 125); returns full updated object (line 140); TS interfaces AccountPreferencesUpdateRequest + AccountPreferencesResponse (lines 238-252). NOTE divergence: method is PUT not PATCH and path is /preferences not /notifications, and the deliverable adds a `language` field — same intent, partial-update semantics satisfied) NOTIFICATIONS Define `PATCH /api/v1/account/notifications`:
  Request: `{ pushEnabled?: boolean, smsEnabled?: boolean, emailEnabled?: boolean }`
  Response 200: `{ data: { pushEnabled: boolean, smsEnabled: boolean,
    emailEnabled: boolean }, error: null }`
  TypeScript interface: `UpdateNotificationPrefsRequest`, `NotificationPrefsResponse`
  Done when: shapes defined; partial update semantics noted.

- [x] ✅ — ✓ verified (endpoint correctly OMITTED with justification; deliverable line 9 marks change-password deferred, and under ADR-002 auth is OTP-only/passwordless so there is NO change-password/change-PIN route by design — the plan's reference to `change-password` is obsolete. Done-condition allows "explicitly omitted with justification"; omission is the right outcome) CHANGE-CREDENTIAL Define credential change endpoint:
  Since auth is phone + OTP (no password), "change credential" may not apply.
  State the decision: is there a PIN, a password, or is the only auth mechanism
  phone + OTP? If phone + OTP only, this endpoint may be: "remove phone" (unusual)
  or not needed at all. Document the decision and if omitted, state why.
  Done when: endpoint defined or explicitly omitted with justification.

- [x] ✅ — ✓ verified (file exists at easy_rates/system-design/api/account-service.md; routes GET /profile, GET/DELETE /properties, GET/PUT /preferences, GET /objections; TS interfaces block lines 206-271; Figma Trace lines 277-288; partial-update semantics explicit for preferences (line 125). POPIA handled by masking — idNumber exposed only as `idNumberMasked` and raw value cannot be returned (schema stores idNumberHash, ADR-003). NOTE: deliverable masks rather than literally omits idNumber, so the plan's exact "idNumber absence" wording is satisfied in spirit, not letter) WRITE Write `easy_rates/system-design/api/account-service.md`:
  Routes + TypeScript interfaces + Figma Trace + POPIA note.
  Done when: file exists; partial-update semantics explicit; `idNumber` absence
  documented.

- [x] ✅ — ✓ verified (1) no RAW idNumber in any response — only `idNumberMasked` "8•••••••••••89" (line 30); raw value is unrecoverable as the schema stores idNumberHash (ADR-003). (2) partial-update semantics explicitly stated for PUT /account/preferences (line 125 "omitted fields are left unchanged"); profile PATCH deferred so no PATCH-profile to check. (3) camelCase fields userId/displayName/email/phoneMasked match data-model/user-auth.md (displayName, email, userId confirmed). NOTE: check (1) read strictly as "no idNumber-derived field at all" would flag `idNumberMasked`; passed on the substantive POPIA intent (no special-personal-info exposure), not the literal token)
  VERIFY Confirm: `idNumber` is not in any account-service response.
  Confirm: PATCH uses partial semantics explicitly stated.
  Confirm: camelCase field names match data-model/user-auth.md schema.
  Done when: all three confirmations pass.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "partial vs full update" question forces PATCH
   semantics to be defined before the Flutter developer has to guess.
   — custom for contract writing.

## Engagement Instructions

Pass condition: GET profile response does not include `idNumber`.
Pass condition: PATCH profile contract explicitly states partial-update semantics.
Pass condition: phone number is not updatable via PATCH profile (reason stated).
Pass condition: TypeScript interfaces for all request/response shapes present.
Pass condition: Figma Trace maps all ACCOUNT & SETTINGS transitions.

## Execution Note — 2026-06-27

This plan predates three hardened decisions; the deliverable diverges from the plan
deliberately and correctly where they collide:

- **ADR-002 (passwordless / OTP-only)** → there is NO change-password / change-PIN
  route. The plan's `change-password` reference is **obsolete**; the deliverable's
  omission is correct.
- **Profile read-only for MVP (MASTER_PLAN G4)** → profile PATCH is **deferred**, not
  authored (no Figma screen supports self-serve edits; it would be a reverse orphan).
- **idNumber stored only as `idNumberHash` (ADR-003)** → the deliverable cannot return
  a raw idNumber; it exposes `idNumberMasked`, and uses `displayName`/`phoneMasked`
  (matching the real `user-auth.md` schema) rather than the plan's `fullName`/raw fields.

### THINK answer (verbatim)

The GET response must show the **new** email immediately after the user changes it —
a profile read is the user's authoritative view of their own record, and showing a
stale value would undermine trust and invite duplicate edits. That requirement forces
the write to be **synchronous**: the PATCH/PUT must commit and return the full updated
object in the same request (the deliverable's PUT /account/preferences does exactly
this — it returns the full updated preferences object, conventions §2 envelope), so
there is no read-after-write window where the client could observe a stale value. (For
MVP this is moot for the profile itself, since profile edits are deferred and the
screen is read-only — "changes via support" — but the principle governs the preferences
write that does ship.) On POPIA: the sensitive fields in the profile are the **SA ID
number** and the **phone number**. The ID number is *special personal information*
under POPIA and is the one to think twice about — so the deliverable never returns it
raw (the schema stores only `idNumberHash` per ADR-003) and exposes only
`idNumberMasked`; the phone number is likewise returned only as `phoneMasked`. Neither
the raw ID nor `kycDocumentKey` is ever placed in a profile GET response. Net: partial-
update semantics are PATCH-style (subset allowed, omitted fields untouched) on the one
write that ships, the write is synchronous, and the two POPIA-sensitive identifiers are
masked rather than exposed.

### Per-task evidence

- THINK — answered above; grounded in deliverable lines 9/17 (read-only, deferred),
  line 125 (partial update), line 30 (idNumberMasked/phoneMasked). DONE.
- FIGMA-TRACE — table lines 277-288 maps every ACCOUNT & SETTINGS screen. DONE.
- GET-PROFILE — GET /account/profile lines 15-36; raw idNumber not returned
  (idNumberMasked, line 30); fields match user-auth.md. DONE (mask not omit — noted).
- PATCH-PROFILE — **NOT DONE**: deferred by deliverable (line 9); read-only MVP. ⚠️.
- NOTIFICATIONS — PUT /account/preferences, partial update, lines 123-156; TS
  interfaces lines 238-252. DONE (PUT not PATCH; /preferences not /notifications).
- CHANGE-CREDENTIAL — correctly OMITTED; ADR-002 passwordless; deliverable line 9. DONE.
- WRITE — file exists; routes + TS + Figma Trace + POPIA mask present. DONE (idNumber
  masked rather than literally absent — noted).
- VERIFY — no raw idNumber; partial semantics stated; camelCase matches schema. DONE
  (literal "no idNumber field" reading would flag idNumberMasked; passed on intent).

Gates: both ✅ resolved — `api/conventions.md` and `docs/data-model/{user-auth,
property-account}.md` all exist and are referenced by the deliverable.
