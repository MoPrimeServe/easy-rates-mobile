# Service Boundary Principles

**Source:** Socratic session on service boundary coupling for EasyRates Node.js monorepo.

---

## The governing paragraph (written to service-map.md Design Principles section)

A service module earns its own boundary when any one of three conditions holds: it has an independent audit trail — its questions must be answerable without entangling another module's state; it changes for a different reason than its neighbors — a provider swap, a tariff rule change, an identity policy update each earn a distinct boundary; or it is reused across more than one flow. Two modules may merge only when none of these conditions holds for either. Across boundaries, synchronous inter-service calls are acceptable exactly when one service cannot complete its transaction without the other's answer — the OTP verify call that gates session creation is the canonical example. Every other cross-service call is asynchronous. The coupling we accept is a narrow synchronous interface at a transaction gate. The coupling we regret is a synchronous call made for information that could have arrived later, and any dependency that entangles one service's audit log with another's.

---

## Three separation criteria

A service stays separate if **any one** of these holds:

### 1. Independent audit trail
Its questions must be answerable without entangling another module's state.

**Example:** `otp-service` — if a ratepayer disputes a login ("I never received an OTP, how was my account accessed?"), you must be able to query OTP delivery records independently of auth session state. If OTP lives inside auth-service, those two facts are entangled. Since disputes over billing access have legal weight in a municipal app, forensic separability is load-bearing here.

### 2. Different change trigger
The module changes for a different reason than its neighbors.

**Example:** `notification-service` changes when the SMS provider changes or WhatsApp support is added. `bill-service` changes when Emfuleni's tariff calculation rules change. These are completely independent triggers — different teams, different external dependencies. No shared audit requirement needed; the change-trigger difference alone justifies the boundary.

**Test:** Ask "why would this module change?" If the answer differs from its neighbor's answer, they belong apart.

### 3. Reuse across flows
The module is needed by more than one flow.

**Example:** `otp-service` — used by the auth flow (phone verification on sign-up), the password-reset flow (forgot password OTP), and potentially future flows (confirm a rate objection submission). If it were merged into auth-service, those other flows would have to import from auth, which is wrong ownership.

---

## Merge condition

Two modules may merge only when **none** of the three conditions holds for either.

---

## Coupling tolerance

### Acceptable: synchronous call at a transaction gate
A synchronous inter-service call is acceptable when one service cannot complete its transaction without the other's answer.

**The canonical example — two OTP calls, two different coupling types:**

| Call | Direction | Type | Why |
|---|---|---|---|
| Send OTP code | auth → otp | **Async** (202) | Delivery is background; user proceeds to OTP entry screen immediately |
| Verify OTP code | auth → otp | **Sync** | Session creation cannot complete without the yes/no; Flutter is blocking with spinner |

The verify call is synchronous by necessity — auth's transaction (creating a session token) cannot complete without otp-service's answer. There is no "proceed and receive the answer later" option here.

### Regrettable: synchronous call for information
A synchronous call where the calling service could have proceeded without the answer and received it asynchronously later.

### Regrettable: entangled audit logs
Any dependency that means you cannot query one service's audit log without going through another's state.

---

## Key insight: "low coupling" does not mean "no dependency"

Separating OTP from auth does not eliminate the dependency — auth still calls otp to verify. Low coupling means the call crosses a **stable, narrow interface**, not that the call disappears. The regrettable form is the one that bleeds internal state across boundaries, not the one that passes a narrow `{ phone, code }` pair.
