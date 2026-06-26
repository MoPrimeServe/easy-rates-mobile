# 📎 File Upload Validation

## Background

⛔ BLOCKED[Gate] — requires parent plan/07-security-design.md LEARN task
(OWASP upload threats understood — this plan operationalises the findings).

File upload is the highest-risk surface for the EasyRates evidence submission flow.
The Flutter app uploads documents (PDF, JPEG, PNG) as evidence for bill objections.
A content-type check on the HTTP header is trivially spoofable — magic-byte checking
via `file-type` reads the actual file bytes before any processing begins.

## Description

Define the complete upload validation pipeline for REST multipart evidence uploads
from the Flutter app: accepted MIME types, maximum file size, `file-type` npm
magic-byte check, AV scan decision, and confirmation that payment card data is
never stored locally (the payment gateway holds it).

## Purpose

To answer: "what is the worst file an attacker could disguise as a PDF — and how
does magic-byte checking catch it when a `Content-Type: application/pdf` header
check would not?"

## Goal

`easy_rates/system-design/docs/security/upload-validation.md` — accepted MIME
types, max size, magic-byte check approach, AV scan decision, payment card
data policy; ready to be consumed directly by api/objection-service.md
(`maxFileSizeBytes` and `acceptedMimeTypes[]` in the upload contract).

## Tasks

- [x] ✅ THINK `/socratic "What is the worst file an attacker could disguise as
  a PDF evidence document — executable code, malicious macro, or something else —
  and at what step in the upload pipeline does magic-byte checking catch it that
  a Content-Type header check cannot? What happens to the user's objection if their
  uploaded file fails magic-byte validation?"`
  Done when: the attack vector is described; the detection point in the pipeline
  is named; the user-facing failure behaviour is stated.

- [x] ✅ LEARN `/unpack "file-type npm package — how to use it with Node.js
  Readable streams and Buffer objects, what file types it detects, how to use it
  with multer multipart middleware, what it returns when a file does not match the
  declared type, known edge cases (corrupted files, files with dual magic bytes)"`
  Done when: you can write a Node.js multer + file-type middleware snippet from
  memory that rejects a file with mismatched magic bytes.

- [x] ✅ DEFINE Define upload validation rules:
  Accepted MIME types (the list that feeds `acceptedMimeTypes[]` in the API contract):
    application/pdf | image/jpeg | image/png
    Justify: evidence documents are typically utility bills (PDF) or photos of the
    meter/property (JPEG, PNG). No Office formats — risk surface too wide.
  Maximum file size in bytes (the value that feeds `maxFileSizeBytes` in the API contract):
    Choose a value that accommodates a scanned A4 PDF at 150 DPI without enabling
    abuse. Justify with a rough size estimate for the largest legitimate upload.
  Magic-byte check:
    Use `file-type` on the first N bytes of every upload before writing to Blob storage.
    If the detected type does not match the declared Content-Type → 422 Unprocessable Entity.
    If `file-type` returns undefined (unrecognised magic bytes) → 422.
  AV scan decision:
    State whether antivirus scanning of uploads is required at pilot stage.
    Options: (a) defer AV scan to production (pilot risk is acceptable with
    magic-byte check alone); (b) integrate a scanning service (Defender for Storage
    on Azure Blob, or ClamAV in the container stack).
    Justify the decision. State the trigger that would require AV scan if not doing
    it at pilot.
  Payment card data:
    Confirm explicitly that no payment card data (PAN, CVV, expiry) is ever stored
    locally. The payment gateway (if needed) holds all card data. EasyRates stores
    only a gateway reference/transaction ID. POPIA + PCI DSS both require this.
  Done when: all five items defined with justification.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/security/upload-validation.md`:
  Accepted MIME types and justification.
  Maximum file size and justification.
  magic-byte check: the step in the pipeline (multer → file-type → write);
  the code-level location (middleware, not route handler).
  AV scan: decision with trigger condition if deferred.
  Payment card data: explicit confirmation it is never stored locally.
  Done when: all five items documented; `maxFileSizeBytes` and `acceptedMimeTypes[]`
  values are machine-readable (integers and string arrays, not prose).

- [x] ✅ VERIFY Cross-reference with api/objection.md (plan referenced `api/objection-service.md`
  — actual filename is `api/objection.md`; pre-existing naming discrepancy):
  `maxFileSizeBytes: 10_485_760` and `acceptedMimeTypes: ['application/pdf', 'image/jpeg',
  'image/png']` match upload-validation.md exactly; `uploadConfig` object returned in
  POST /objection 201 response. ✓ verified

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "worst file disguised as PDF" framing forces the
   magic-byte rationale to be grounded in an actual attack vector.
   alt: `/unpack` ✅ — `file-type` npm integration with multer if the multipart
   middleware pattern is unfamiliar.

## Engagement Instructions

Pass condition: accepted MIME types list specified as a string array (not prose).
Pass condition: maximum file size specified as an integer in bytes.
Pass condition: magic-byte check placement stated — middleware, before write to Blob storage.
Pass condition: AV scan decision documented with "yes, using X" or "deferred until Y trigger."
Pass condition: payment card data policy states explicitly that no PAN/CVV/expiry is stored.
Pass condition: `maxFileSizeBytes` and `acceptedMimeTypes[]` values are machine-readable
and match the values used in api/objection-service.md.
