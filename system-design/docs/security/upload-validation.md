# EasyRates — File Upload Validation

**Status:** Decided  
**Date:** 2026-06-20  
**Downstream:**
- `api/objection.md` — `maxFileSizeBytes` and `acceptedMimeTypes[]` values below are the
  authoritative source. The contract must match these integers and strings exactly.
  Any divergence is a gap.
- Flutter `file_picker` — the objection creation response includes these values so the
  client constrains file selection before upload, not after.

---

## Machine-readable constants

These are the values that feed every downstream contract and client implementation.

```typescript
// shared/uploadConfig.ts — single source of truth; import everywhere
export const UPLOAD_CONFIG = {
  acceptedMimeTypes: [
    'application/pdf',
    'image/jpeg',
    'image/png',
  ] as const,

  maxFileSizeBytes: 10_485_760, // 10 MiB

  maxFilesPerObjection: 5,
} as const
```

No other file in the codebase hardcodes these values. Every service handler, every
middleware, and every API contract response body reads from `UPLOAD_CONFIG`.

---

## Rule A — Accepted MIME types

```
acceptedMimeTypes: ['application/pdf', 'image/jpeg', 'image/png']
```

### Justification

Evidence documents in a billing objection are either a scanned utility bill (PDF), a
photograph of a meter or property (JPEG), or a screenshot of a previous statement (PNG).
No other format serves a legitimate evidence purpose.

**Formats explicitly excluded and why:**

| Format | MIME type | Reason excluded |
|---|---|---|
| Word / Office | `application/vnd.openxmlformats-officedocument.*` | Macros, embedded OLE objects, VBA scripts. A municipality reviewer opening a `.docx` on Windows faces arbitrary code execution. Surface too wide. |
| ZIP / archive | `application/zip`, `application/x-tar` | Archives can contain executables, nested archives, or zip-bomb payloads. Content cannot be inspected without extraction. |
| HTML | `text/html` | Stored in blob and served to a browser, HTML executes — XSS or redirect injection is trivial. |
| GIF | `image/gif` | No evidence use case. Animated GIFs with embedded scripts (historical CVEs). |
| TIFF | `image/tiff` | Legitimate scan format but rarely from mobile devices. Excluded to keep the surface minimal at pilot. Add via ADR if a scanning-workflow use case emerges. |
| Executables | `application/x-executable`, `application/x-msdownload`, etc. | Self-explanatory. Magic-byte check catches these even when disguised as PDF. |

---

## Rule B — Maximum file size

```
maxFileSizeBytes: 10_485_760   // 10 MiB exactly
```

### Derivation from envelope.md

Envelope.md states:
> "Objections × 3 files × 3 MB avg (mobile photos 2–5 MB; PDF scans 1–3 MB)"

The 3 MB figure is the average. The limit is set at the P99 tail:

| File type | Typical range | P99 upper bound |
|---|---|---|
| Mobile JPEG (meter photo) | 2–5 MB | ~8 MB (48 MP flagship camera, low-compression setting) |
| PDF scan (utility bill) | 1–3 MB | ~5 MB (multi-page, colour, 300 DPI) |
| PNG screenshot (previous statement) | 3–8 MB | ~10 MB (high-DPI screen, no compression) |

10 MiB covers P99 for all three types. A ratepayer using a prepaid entry-level device
(2–5 MP camera, compressed JPEG output) will never approach this limit.

### Storage cost impact

At P99 all files (10 MB each):
- Production (7,500 files): 7,500 × 10 MB = 75 GB
- Azure Blob LRS Hot SA North: ~$1.69/month

At envelope average (3 MB):
- Production: 7,500 × 3 MB = 22.5 GB → ~$0.51/month

The limit is not a cost driver. Its purpose is abuse prevention: a 100 MB or 1 GB
upload would saturate the App Service B1 memory during the multer buffering step.
At 10 MiB per upload and B1's 1.75 GB RAM (7 services sharing one plan at pilot),
a single upload consumes <1% of available memory.

---

## Rule C — MIME validation: magic-byte check via `file-type`

### Why Content-Type header checking is insufficient

The HTTP `Content-Type` header is set by the client. A one-line curl command overrides it:

```bash
curl -F "file=@malware.exe;type=application/pdf" https://api.easyrates.co.za/objections/x/evidence
```

The file extension is equally unreliable — a file renamed from `webshell.php` to
`meter-photo.jpg` passes an extension check. Neither check reads what the file actually is.

### Why magic-byte checking works

Every file format begins with a format-specific byte sequence. The PDF format starts with
`%PDF-` (`25 50 44 46 2D`). JPEG starts with `FF D8 FF`. PNG starts with
`89 50 4E 47 0D 0A 1A 0A`. An EXE (PE format) starts with `4D 5A` (`MZ`).

The `file-type` npm package reads the first 4,100 bytes of the file buffer and matches
against ~200 magic-byte signatures. It returns the detected MIME type or `undefined`
if no known signature is found.

**The attack it catches:** A file that begins with valid PDF magic bytes but contains
executable code or macros in the body is detected as `application/pdf` by `file-type`.
This is the polyglot / dual-magic-byte scenario. `file-type` does not catch malicious
content within a legitimately-typed file — that is the responsibility of the AV scan
(see Rule D). However, the most dangerous upload attacks (EXE disguised as PDF,
PHP webshell with forged Content-Type) are caught because their magic bytes do not
match the declared type, or because they are not in the allowed-type list.

**What happens when the check fails:** The file is rejected before it reaches Azure Blob
Storage. The multer buffer is discarded. The client receives 422 with
`error.code: "invalid_file_type"`. The objection remains in DRAFT status; the user
is prompted to re-upload a valid file.

### Library

**Package:** `file-type` (npm)  
**Why this package:** Purpose-built for magic-byte detection. Covers all three allowed
types (PDF, JPEG, PNG) with reliable signatures. Actively maintained.
Reads from a `Buffer` directly — no filesystem access required, which suits the
`multer.memoryStorage()` pipeline.

**ESM compatibility note:** `file-type` v14+ is pure ESM. If the backend project is
CommonJS, use a dynamic import inside an async function:

```typescript
const { fileTypeFromBuffer } = await import('file-type')
```

If the backend is ESM (recommended for new Node.js TypeScript projects), import
statically:

```typescript
import { fileTypeFromBuffer } from 'file-type'
```

Do not use `file-type` v13 or earlier — they are CommonJS but no longer maintained
and lack signatures for recent format variants.

### Pipeline position

```
Flutter multipart POST
        │
        ▼
   multer.single('file')              ← memory storage, 10 MiB hard stop
   (multer rejects >10 MiB → 413)
        │
        ▼
   validateMimeType middleware         ← magic-byte check (Rule C)
   (file-type reads req.file.buffer)
   (rejects non-PDF/JPEG/PNG → 422)
        │
        ▼
   evidenceHandler
        │
        ├── write to Azure Blob Storage with DETECTED (not declared) Content-Type
        ├── set Content-Disposition: attachment on blob metadata
        └── INSERT EvidenceFile row (storageKey, filename, mimeType=detected, sizeBytes)
```

The detected MIME type — not the client-declared `Content-Type` header — is used when
writing the blob metadata. When the file is later served for download, the correct
Content-Type is derived from this stored value, not from the original HTTP header.

### Middleware implementation

```typescript
// shared/middleware/validateMimeType.ts
import { Request, Response, NextFunction } from 'express'
import { UPLOAD_CONFIG } from '../uploadConfig'

export async function validateMimeType(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  const buffer = req.file?.buffer
  if (!buffer) {
    res.status(400).json({
      data: null,
      error: { code: 'file_missing', message: 'No file was attached.' },
    })
    return
  }

  const { fileTypeFromBuffer } = await import('file-type')
  const detected = await fileTypeFromBuffer(buffer)

  const allowed: readonly string[] = UPLOAD_CONFIG.acceptedMimeTypes

  if (!detected || !allowed.includes(detected.mime)) {
    res.status(422).json({
      data: null,
      error: {
        code: 'invalid_file_type',
        message: 'File type not supported. Upload PDF, JPG, or PNG only.',
        details: {
          detectedType: detected?.mime ?? 'unknown',
          allowedTypes: [...UPLOAD_CONFIG.acceptedMimeTypes],
        },
      },
    })
    return
  }

  // Attach detected type for handler use; do not trust req.file.mimetype
  ;(req as Request & { detectedMimeType: string }).detectedMimeType = detected.mime
  next()
}
```

```typescript
// modules/objection/objection.router.ts
import multer from 'multer'
import { UPLOAD_CONFIG } from '../../shared/uploadConfig'
import { validateMimeType } from '../../shared/middleware/validateMimeType'
import { jwtMiddleware } from '../../shared/middleware/jwt'
import { writeLimiter } from '../../shared/rateLimiters'

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: UPLOAD_CONFIG.maxFileSizeBytes },
})

router.post(
  '/:id/evidence',
  jwtMiddleware,          // 1. verify JWT, attach req.user
  writeLimiter,           // 2. rate limit (20/hour/userId from rate-limits.md)
  upload.single('file'),  // 3. multer: buffer to memory, reject >10 MiB with 413
  validateMimeType,       // 4. magic-byte check, reject non-PDF/JPEG/PNG with 422
  evidenceHandler,        // 5. write to Azure Blob Storage, insert EvidenceFile row
)
```

### Error responses from this pipeline

| Condition | HTTP | `error.code` |
|---|---|---|
| No file in request | 400 | `file_missing` |
| File exceeds 10 MiB | 413 | (multer default — override with `limits.fileSize` handler if custom envelope is needed) |
| File type not in allowlist | 422 | `invalid_file_type` |
| File type unrecognised (undefined magic bytes) | 422 | `invalid_file_type` |

---

## Rule D — Antivirus scan decision

**Decision: Defer AV scan to production launch. No AV at pilot.**

### Pilot risk profile

At pilot scale:
- ~750 files uploaded over 12 months (~20 per month)
- All files stored in a private Azure Blob container (no anonymous public access)
- Files are served only to the authenticated user who uploaded them, or to municipality
  staff via a controlled access path — not to arbitrary internet users
- Files are never executed by the EasyRates backend — they are stored as opaque blobs
  and streamed back as downloads
- The primary attack surface for uploaded malware is a municipality reviewer opening a
  file on their workstation. At pilot, this path is not yet live (no municipality system
  integration in Phase 1 MVP)

Magic-byte checking eliminates the file-type confusion attack class. The remaining
unmitigated risk at pilot is **malicious content within a legitimately-typed file**
(e.g., a PDF with embedded JavaScript that exploits a PDF reader, or a JPEG with
a hidden payload in EXIF metadata). This risk is accepted at pilot because:
1. The attacker must be an authenticated ratepayer (not anonymous)
2. The file is not executed or rendered by the server
3. The download path at pilot is not yet connected to municipality workstations

### Production trigger

Activate AV scanning when **any** of the following conditions is met:
- Municipality system integration is live (files are opened by municipality staff outside
  EasyRates)
- File volume exceeds 1,000 uploads/month (automated scanning becomes cost-effective)
- Any security incident involving uploaded files, regardless of scale

### Recommended AV path: Azure Defender for Storage

**Not ClamAV.** ClamAV is self-hosted, requires a dedicated container, needs signature
update scheduling, and adds operational overhead unjustified for a pilot-to-production
product. False positive rates require a triage process.

**Azure Defender for Storage** (malware scanning add-on) scans every blob on upload via
Event Grid triggers. Scanning is asynchronous — files are written to blob storage and
tagged with a scan result (Clean / Malicious / Timeout) within seconds. The objection-service
polls the blob metadata tag before serving a file for download.

Approximate cost at production (12-month basis):
- Storage account plan: ~$0.02/month
- Per-GB scanning: ~$0.15/GB (verify current rate at Azure pricing page before activating)
- At 22.5 GB/year production: ~$0.15 × 22.5 = **~$3.38/year**

This is a negligible cost at production scale. The cost does not justify a deferred decision
beyond the production launch milestone.

### Integration note (for when activated)

```typescript
// evidenceHandler — add after Blob write, before EvidenceFile INSERT
const blobClient = containerClient.getBlobClient(storageKey)
await pollForScanResult(blobClient, { timeoutMs: 30_000 })
// Poll blob metadata tag 'Malware Scanning Scan Result'
// If 'Malicious': delete blob, return 422 { code: 'file_malware_detected' }
// If 'Timeout': accept file, flag for async re-scan (do not block upload)
// If 'Clean': proceed to INSERT EvidenceFile row
```

Do not block the upload for longer than 30 seconds. If the scan times out, accept the
file and flag it for async re-scan. A timed-out upload that blocks the submission flow
is worse UX than a delayed scan result.

---

## Rule E — Payment card data policy

EasyRates is a billing query and objection platform. It is **not** a payment processor.

**No payment card data (PAN, CVV, expiry date, PIN) is collected, stored, processed, or
transmitted by EasyRates at any layer — database, blob storage, logs, or API responses.**

If a ratepayer's uploaded evidence document happens to contain a card number (e.g., a
bank statement showing a card number), EasyRates does not extract, index, or process that
information. It is stored as an opaque blob.

**If payment functionality is added in a future phase:**
- Integrate a PCI DSS Level 1 certified payment gateway operating in South Africa
  (Peach Payments, PayFast, or equivalent)
- EasyRates stores only the gateway's transaction reference ID — never the card data
- The payment form is rendered by the gateway SDK (hosted field or redirect) — card
  numbers never pass through EasyRates servers
- This approach maintains PCI DSS SAQ-A eligibility and keeps EasyRates out of PCI DSS
  scope entirely

---

## Flutter client integration

The objection creation response (`POST /objections/draft`) includes upload constraints
so the Flutter `file_picker` validates before upload, not after:

```json
{
  "objectionId": "clxxx",
  "status": "DRAFT",
  "uploadConfig": {
    "maxFileSizeBytes": 10485760,
    "acceptedMimeTypes": ["application/pdf", "image/jpeg", "image/png"],
    "maxFilesPerObjection": 5
  }
}
```

The Flutter client uses these values to:
1. Restrict `FilePicker.platform.pickFiles(allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'])`
2. Check `file.size <= maxFileSizeBytes` before opening the upload request
3. Show a pre-upload error if the file fails either check — no wasted network round trip

Client-side validation is UX only. Server-side magic-byte check is the security control.
Both are required.

---

## Naming discrepancy (flag for resolution)

`api/objection.md` uses `POST /objection/:id/documents` (base path `/objection`, singular).  
`service-map.md` and `rate-limits.md` use `POST /objections/:id/evidence` (plural, different noun).

These refer to the same endpoint. The path must be unified before `api/objection.md` is
locked. Resolve in the api-contracts plan (plan/09) before implementation.
