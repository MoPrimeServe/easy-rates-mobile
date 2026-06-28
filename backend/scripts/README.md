# EasyRates — Mobile Customer-Journey Test Harness

Three ways to walk the **full** EasyRates mobile customer journey against the live
backend, all hitting the single gateway origin `http://localhost:8080/api/v1`:

| File | Tool | Use it for |
|---|---|---|
| `EasyRates.postman_collection.json` | Postman / newman | Click-through journey with auto-chaining test scripts. |
| `api.http` | VS Code **REST Client** | Inline, copy-the-token-as-you-go manual walkthrough. |
| `e2e.sh` | bash + curl | Headless, self-asserting smoke test (`✓/✗`, `E2E: N/N passed`). |

The journey is organised into the **seven Figma stages**: Onboarding · Find
Property · Bill Review · Evidence & Challenge · Submission · Tracking &
Resolution · Account & Settings.

---

## 0. Bring the stack up (mock mode)

```bash
cd backend
pnpm dev:mock          # boots all 8 services + gateway with OTP_MOCK=true
```

Preconditions (already true in dev): Postgres `easyrates_dev` is **seeded**
(`pnpm db:seed`) and Redis is up. `pnpm dev:mock` multiplexes every service's
stdout — keep that terminal visible (the OTP code is printed there, see below).

### Mock vs. real OTP

- **Mock (`OTP_MOCK=true`, what `pnpm dev:mock` sets).** No SMS, no Twilio. The
  otp-service prints the plaintext code to its stdout:
  ```
  [otp][mock] code for +27821234567 (LOGIN): 481920
  ```
  and the public `POST /otp/resend` returns the same code as `mockCode` in its
  JSON body. The harness reads the code one of those two ways.
- **Real (`OTP_MOCK=false`).** Twilio Verify owns the code; there is **no**
  `mockCode` and nothing in the log. The harness's automatic OTP capture does not
  apply — you would type the SMS code by hand. These scripts target **mock mode**.

---

## 1. Run the headless e2e (`e2e.sh`)

```bash
cd backend
export MUNICIPAL_WEBHOOK_SECRET=...        # the VALUE from .env (Tracking step needs it)
pnpm e2e                                   # == bash scripts/e2e.sh
```

For the **fast, log-based** OTP capture (no resend cooldown wait), point the
script at the file you redirected `pnpm dev:mock` into:

```bash
pnpm dev:mock > /tmp/easyrates.log 2>&1 &
export MUNICIPAL_WEBHOOK_SECRET=...
E2E_LOG=/tmp/easyrates.log bash scripts/e2e.sh
```

Without `E2E_LOG`, the script falls back to `POST /otp/resend` for `mockCode` and
honours the one-time 30s resend cooldown automatically (slower but self-contained).

What it does, asserting every step:

1. **Onboarding** — `register/start` → verify → `register` (fresh, timestamped
   phone, Luhn-valid ID) → `auth/session` → `auth/kyc` (PDF) → `refresh` → `logout`.
2. Logs in as the **seeded ratepayer** (`+27821234567`) who owns the seeded
   property/bill/line-items the data stages need.
3. **Find Property** → **Bill Review** → **Evidence & Challenge** (draft +
   real-PNG evidence + sufficiency) → **Submission** (async submit, polls until
   the worker assigns the `ELM-2026-NNNNNN` refNumber).
4. **Tracking & Resolution** — status, the **municipality webhook**
   (`MORE_INFO_REQUESTED` → re-upload auto-returns to `UNDER_REVIEW` → `UPHELD`
   with adjustment), close.
5. **Account & Settings** + notifications.

Output ends with `E2E: N/N passed`; it exits non-zero if any step fails.

> **Re-runnability.** Each run uses a new phone, and the script resets the
> dev-only rate-limit keys at start (the AUTH limiter is IP-scoped 10/15min; one
> journey spends ~3 — repeated runs would otherwise trip it). The reset is a
> no-op if `redis-cli` is absent, and is justified for a **local mock** stack
> only. The objection draft falls through line items so a prior run's submitted
> objection doesn't block the next run. The seed user has 8 line items, and a
> submitted objection permanently retires the charge it disputes; run
> **`pnpm db:seed`** to refresh — the seed resets the harness's objections
> (everything except the canonical `ELM-2026-000001`) for the seed user, handing
> back clean, re-disputable line items.

---

## 2. Run the Postman collection

**Import** `EasyRates.postman_collection.json` into Postman, then:

1. Set the collection variable **`municipalSecret`** to the value of
   `MUNICIPAL_WEBHOOK_SECRET` from `backend/.env` (Tracking & Resolution needs it).
2. In the **Upload Proof of Address**, **Attach Evidence**, and **Re-upload
   Evidence** requests, select a real local file in the *Body → form-data → file*
   field (a PNG/JPEG/PDF — the server validates by magic bytes, so a fake file
   with only header bytes is rejected).
3. Run the whole collection with the **Collection Runner** (top-to-bottom), or
   send the requests in order.

The collection auto-chains via **test scripts**: it mints a fresh phone per run,
calls `/otp/resend` (retrying past the cooldown) to read the `mockCode` and
verify, captures `registrationToken` then the session tokens, sets
`Authorization: Bearer {{accessToken}}` at the collection level, and threads
`billId` / `lineItemId` / `objectionId` / `objectionRef` through the journey.
Every request carries a `pm.test` asserting the expected status + a key field.

### Optional: run it headlessly with newman

```bash
cd backend
# files for the three upload steps:
#   (point newman's collection at real file paths — the committed collection keeps
#    the file fields empty so the Postman UI prompts you to choose a file)
npx --yes newman run scripts/EasyRates.postman_collection.json \
  --env-var "municipalSecret=$MUNICIPAL_WEBHOOK_SECRET" \
  --delay-request 300
```

> newman cannot supply a file to an empty form-data `file` field; for a fully
> green newman run, inject real file paths into a copy of the collection (or just
> rely on `e2e.sh`, which exercises the identical requests with real files).

---

## 3. Walk it in VS Code (`api.http`)

Install the **REST Client** extension (`humao.rest-client`), open `api.http`, and
click **Send Request** above each block top-to-bottom. Fill the `@municipalSecret`
variable from `.env`, paste the plaintext OTP into `@otpCode` / `@loginOtpCode`
(from the dev:mock log or the `/otp/resend` response), and copy each response's
token / id into the matching `@`-variable as you progress. The `auth/kyc` and
evidence steps reference `./proof.pdf` and `./meter.png` — drop any small real
PDF/PNG with those names next to `api.http`, or edit the paths.

---

## Out of scope (deliberately, and absent from the backend)

- **Forgot-Password / password reset** — auth is **passwordless OTP-only**
  (ADR-002); there is no password to recover. A locked-out user simply logs in
  again with a fresh OTP.
- **WhatsApp onboarding** — not part of the MVP backend.
- **Payments** — not part of the MVP backend.

None of these have routes; they are documented here so the absence is intentional,
not an omission.
