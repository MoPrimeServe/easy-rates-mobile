# Node.js TypeScript Monorepo — Service Modules as Bounded Contexts

**Source:** Unpack session on monorepo-module pattern vs true microservices.

---

## What it is

A TypeScript monorepo is a single Git repository containing all project code, organised into **modules** — folders with clear internal structure and controlled borders. Each module acts like a service: it owns its own route handlers, business logic, database models, and validation. Other modules interact with it only through a single barrel export file.

The entire thing runs as **one Node.js process**. Separation is logical (folder structure, import rules), not physical (separate servers, separate databases).

---

## Components (in dependency order)

### 1. The module folder
The basic unit. A folder named after one bounded context. Everything belonging to that context lives here.

```
src/modules/auth/
src/modules/otp/
src/modules/bill/
src/modules/objection/
```

### 2. The barrel file (`index.ts`)
Every module folder has one `index.ts` listing what it exposes to the outside world. Other modules may **only** import from this file — never from internal files like `auth.service.ts` directly. This is the enforced border.

```ts
// src/modules/otp/index.ts
export { sendOtp, verifyOtp } from './otp.service'
export type { OtpResult } from './otp.types'
```

### 3. The validation file
Zod schemas — one per incoming request shape. Each module validates its own inputs. Nothing outside the module decides what is valid for it.

```ts
// src/modules/auth/auth.validation.ts
import { z } from 'zod'
export const LoginSchema = z.object({
  phone: z.string().regex(/^\+27\d{9}$/)
})
```

### 4. The service file
Business logic functions. Does the actual work — checking rules, calling Prisma, calling other modules. No HTTP here; takes plain inputs, returns plain outputs.

```ts
// src/modules/auth/auth.service.ts
import { sendOtp } from '../otp'  // imports from otp barrel only
export async function initiateLogin(phone: string) { ... }
```

### 5. The route handler file
Connects HTTP to the service. Reads the request, runs validation, calls the service, sends the response. No business logic.

```ts
// src/modules/auth/auth.routes.ts
router.post('/login', async (req, res) => {
  const data = LoginSchema.parse(req.body)
  const result = await initiateLogin(data.phone)
  res.status(202).json(result)
})
```

### 6. The Prisma schema
One `schema.prisma` file for the whole project. Each module logically "owns" certain models by convention — the bill module owns `Bill` and `BillLine`, the auth module owns `Session`. No module writes to another module's tables.

### 7. The app entry point (`app.ts`)
Mounts all module routers onto one Express app. The only file that knows about every module.

```ts
app.use('/auth', authRouter)
app.use('/otp', otpRouter)
app.use('/bills', billRouter)
```

---

## Request pipeline

How `POST /auth/login` flows end-to-end:

```
Flutter → POST /auth/login
  → app.ts routes to authRouter
  → auth.routes.ts: LoginSchema.parse(req.body)
    → invalid: 400, stops here
    → valid: calls initiateLogin(phone)
      → auth.service.ts calls sendOtp(phone) from otp barrel
        → otp.service.ts generates code, writes OtpRecord via Prisma
        → otp.service.ts enqueues async SMS dispatch
        → returns { dispatched: true }
      → auth.service.ts returns { status: 'otp_sent' }
  → auth.routes.ts sends 202 { status: 'otp_sent' }
← Flutter receives 202, navigates to OTP entry screen
```

The call from `auth.service.ts` to `sendOtp` is a **function call** — not HTTP. Zero network latency. Type-safe: if `sendOtp`'s signature changes, TypeScript fails the build at `auth.service.ts`.

---

## Monorepo module vs true microservices

| | Monorepo module | True microservices |
|---|---|---|
| Inter-service calls | Function call (0 ms) | HTTP/gRPC (~1–10 ms per hop) |
| Type safety across services | Yes — TypeScript catches mismatches at build | No — wrong payload only fails at runtime |
| Deployment | One deploy for everything | Each service deploys independently |
| Scaling | Scale whole app or nothing | Scale individual services |
| Operational complexity | Low — one process, one DB connection pool | High — service discovery, distributed tracing, separate CI |
| Accidental coupling | Possible — a developer imports past the barrel | Impossible — no import, only a network call |
| Right choice at pilot scale | **Yes** | No — premature for EasyRates |

The monorepo-module pattern gives logical boundaries at zero operational cost. The discipline cost is real: without enforced import rules, developers reach past the barrel. Enforce with an ESLint `no-restricted-imports` rule or a path alias convention.

---

## EasyRates folder structure

```
src/
  modules/
    auth/           → src/modules/auth
    otp/            → src/modules/otp
    property/       → src/modules/property
    account/        → src/modules/account
    bill/           → src/modules/bill
    objection/      → src/modules/objection
    notification/   → src/modules/notification
    status/         → src/modules/status
    queue-consumer/ → src/modules/queue-consumer
  prisma/
    schema.prisma
  app.ts
  server.ts
```

These nine module names are **locked** — used unchanged across all downstream plans (03, 06, 07, 08, 09, 10).

---

## Key insight: function call, not HTTP

In a monorepo module, when `auth.service.ts` calls `verifyOtp` from `otp-service`, it is calling a TypeScript function — not making an HTTP request. This is why the hop-count stays at ≤ 2 synchronous hops for every EasyRates flow: the cross-module calls within the backend are not network hops.
