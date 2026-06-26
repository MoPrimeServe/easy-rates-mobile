# 🔔 Notification & Municipality Response Models

## Background

⛔ BLOCKED[Gate] — requires plan/00-erd.md WRITE task (ERD complete — FK from
Notification to User is set; FK from MunicipalityResponse to Objection is set).
⛔ BLOCKED[Gate] — requires plan/04-objection.md WRITE task (Objection model
defined — MunicipalityResponse references Objection and its status enum).

Notification is the delivery mechanism for the TRACKING & RESOLUTION Figma flow.
Three channels are explicit in the Figma PDF: push, SMS, and email. MunicipalityResponse
is the CRM ingestion entity — municipality status updates flow in via webhook and
feed the objection tracking state machine.

## Description

Write the complete Prisma schema blocks for `Notification` and `MunicipalityResponse`.
Includes: 3-value `NotificationChannel` enum; `MunicipalityResponse` FK to Objection
with state-transition implication; indexes on `userId + isRead` for notification list.

## Purpose

To answer: "a municipality sends a CRM status update — how does that update flow
from the ingestion webhook to the user's notification, and what does each step look
like at the database level?"

## Goal

`easy_rates/system-design/docs/data-model/notification.md` — complete Prisma schema
blocks for `Notification` and `MunicipalityResponse`; `NotificationChannel` enum
with 3 values; index justifications; state-transition note.

## Tasks

- [x] ✅ THINK `/socratic "When the municipality sends a CRM status update for an
  objection, what sequence of database writes happens — and where can that sequence
  go wrong? If a MunicipalityResponse is received for an Objection that is already
  UPHELD, should the database allow the status to be changed again, or should it
  be locked? And who is responsible for the Notification — is it created at the same
  time as the MunicipalityResponse, or by a separate notification-service job?"`
  Done when: the write sequence (MunicipalityResponse insert → Objection status
  update → Notification create) is described; the duplicate-status-update scenario
  is addressed; the notification creation responsibility is stated.

- [x] ✅ ENUM Lock in the `NotificationChannel` enum. Three channels from the
  Figma PDF:
  ```prisma
  enum NotificationChannel {
    PUSH
    SMS
    EMAIL
  }
  ```
  Done when: enum is written; 3 values match the Figma flow.

- [x] ✅ FIELDS Write the Prisma schema block for `Notification`:
  Fields to consider:
  - `id` (UUID)
  - `userId` (FK to User; onDelete: Cascade — if user is deleted, notifications go too)
  - `objectionId` (FK to Objection? — optional, not all notifications are objection-related)
  - `channel` (NotificationChannel enum)
  - `title` (String)
  - `body` (String)
  - `isRead` (Boolean @default(false))
  - `sentAt` (DateTime — when the notification was dispatched via the channel)
  - `readAt` (DateTime? — when the user read it in the app)
  - `createdAt` (DateTime @default(now()))
  - Relation: `user User`, `objection Objection?`
  Decide: is `objectionId` nullable (notifications may not be about objections)?
  Justify.
  Done when: every field has a Prisma type; index on `[userId, isRead]` included.

- [x] ✅ MR-FIELDS Write the Prisma schema block for `MunicipalityResponse`:
  Fields to consider:
  - `id` (UUID)
  - `objectionId` (FK to Objection; onDelete: Restrict — do not delete objection
    if it has CRM responses; audit trail)
  - `newStatus` (ObjectionStatus enum — the status the municipality is setting)
  - `previousStatus` (ObjectionStatus enum — the status before this update)
  - `responseText` (String? — municipality's written response or reason)
  - `respondedAt` (DateTime — when the municipality issued the response)
  - `rawPayload` (Json? — the raw CRM webhook payload for audit; POPIA note: may
    contain PII from the CRM system)
  - `createdAt` (DateTime @default(now()))
  - Relation: `objection Objection`
  Note: `rawPayload` is a Json field that may contain PII from the municipality
  CRM. Cross-reference with popia-inventory.md.
  Done when: every field has a Prisma type; `onDelete: Restrict` justified;
  `rawPayload` POPIA note included.

- [x] ✅ INDEXES Justify indexes:
  `@@index([userId, isRead])` on Notification — the notification list query
  fetches all unread notifications for a user; this composite index serves it.
  `@@index([objectionId])` on MunicipalityResponse — the objection tracking
  view fetches all municipality responses for an objection.
  `@@index([userId])` on Notification alone — the "mark all as read" endpoint
  updates all notifications for a user by userId.
  Done when: all indexes justified against named Figma flow queries.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/data-model/notification.md`:
  Full Prisma schema blocks for Notification and MunicipalityResponse;
  NotificationChannel enum; index justifications; state-transition note;
  rawPayload POPIA cross-reference.
  Done when: file exists; 3-channel enum documented; POPIA note on rawPayload.

- [x] ✅ VERIFY Cross-reference with api/notification-service.md (once written):
  confirm `isRead` is the field the Flutter client PATCH endpoint updates.
  Cross-reference with api/municipality-service.md: confirm `MunicipalityResponse`
  fields match the expected webhook payload fields.
  Done when: field names in schema match API contract field names.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the CRM-update write sequence question forces the
   schema to model the state machine correctly.
   — custom for schema writing.

## Engagement Instructions

Pass condition: `NotificationChannel` enum has exactly 3 values (PUSH, SMS, EMAIL).
Pass condition: Notification has `@@index([userId, isRead])`.
Pass condition: MunicipalityResponse has `onDelete: Restrict` on `objectionId`
with a written audit-trail justification.
Pass condition: `rawPayload` (Json?) on MunicipalityResponse has a POPIA note.
Pass condition: state-transition note describes the write sequence for a CRM update.
