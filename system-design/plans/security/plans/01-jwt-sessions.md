# 🔑 JWT Security Model

## Background

⛔ BLOCKED[Gate] — requires parent plan/07-security-design.md THINK task (blast-radius
question answered — JWT scope must be user-scoped before algorithm is chosen).

The JWT model is the primary access control mechanism for the Flutter client. Every
API endpoint (except the three unauthenticated ones) validates the access token before
processing the request. A wrong decision here — algorithm choice, TTL, storage — cannot
be patched without invalidating all active sessions and forcing re-login for every user.

## Description

Define the full JWT security model for the Flutter client: algorithm (HS256 vs RS256),
access token TTL and in-memory Flutter storage rationale, refresh token TTL and storage
(`flutter_secure_storage`), rotation policy, and revocation strategy.

## Purpose

To answer: "if a Flutter access token is extracted from device memory, what can the
attacker do — and what prevents them from maintaining that access indefinitely?"

## Goal

`easy_rates/system-design/docs/security/sessions.md` — all five JWT sub-decisions
made and documented; Flutter storage location stated for both token types; revocation
strategy justified.

## Tasks

- [x] ✅ THINK `/socratic "If an attacker extracts a Flutter access token from device
  memory, what is the blast radius — and what is the mechanism that limits how long they
  can use it? If the refresh token is also extracted from flutter_secure_storage, what
  stops the attacker from generating access tokens indefinitely?"`
  Done when: the failure scenario is described in writing; the TTL and rotation
  decisions are motivated by that scenario, not by a default value.

- [x] ✅ LEARN `/unpack "JWT HS256 vs RS256 — symmetric vs asymmetric signing, when
  key rotation matters, Node.js jwt library options (jsonwebtoken vs jose), access
  token in-memory vs on-disk on mobile, flutter_secure_storage security model and
  what 'secure' means on iOS vs Android, refresh token rotation on every use vs on
  expiry only"`
  Done when: you can justify the algorithm choice and storage location for both
  token types from first principles.

- [x] ✅ DECIDE Make and document all five sub-decisions:
  a. Algorithm: HS256 or RS256? Justify (key rotation requirement, Node.js ops
     complexity, token verification overhead).
  b. Access token TTL: choose a value and justify against the blast-radius scenario
     from THINK — shorter TTL limits damage window; too short means constant refresh.
  c. Refresh token TTL: choose a value and justify (session duration users expect
     on a municipal billing app — annual tax cycle? Monthly billing cycle?).
  d. Rotation policy: rotate refresh token on every use (more secure, more ops
     complexity for concurrent requests) or on expiry only (simpler, longer window)?
     Justify.
  e. Revocation: Redis blacklist for access tokens (real-time revocation, ops
     overhead) or short TTL + refresh rotation (simpler, small revocation lag)?
     Justify. State the maximum lag before a revoked token stops working.
  Done when: all five sub-decisions are written with rationale; no sub-decision
  says "to be decided."

- [x] ✅ FLUTTER-STORAGE Document the Flutter storage model:
  Access token: stored in-memory only (Riverpod provider, Bloc state, or equivalent)
  — never written to disk. Explain why: on-disk storage survives app restart and
  device backup, making token theft via backup extraction possible.
  Refresh token: stored in `flutter_secure_storage` — uses iOS Keychain on iOS,
  Android Keystore system on Android. Explain the security properties of each.
  Dio interceptor: describe the transparent refresh flow — on 401, the Dio interceptor
  calls the refresh endpoint, updates the in-memory access token, and retries the
  original request.
  Done when: storage location stated for both token types with the security rationale
  for each choice.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/security/sessions.md`:
  One section per sub-decision; Flutter storage model section; Dio interceptor
  integration note.
  Done when: all five decisions documented; Flutter storage model documented;
  document is self-contained (a developer can implement from this alone).

- [x] ✅ VERIFY Blast-radius test: if an attacker has both the access token and
  the refresh token, walk through the exact steps they can take and the exact
  mechanism that eventually terminates their access.
  Expected answer: access token expires after `ttl_seconds`; refresh token rotation
  means each refresh invalidates the prior refresh token; revocation via blacklist
  or forced rotation terminates access within the stated lag window.
  Done when: the sequence is written; every step has a named technical mechanism;
  no step relies on "the attacker gives up."

## Recommended skill

▶ `/socratic` ✅ — THINK task; the token-extraction blast-radius framing forces TTL
   and rotation decisions to be grounded in actual threat scenarios.
   alt: `/unpack` ✅ — JWT algorithm comparison and flutter_secure_storage security
   model if either is not already well understood.

## Engagement Instructions

Pass condition: all five sub-decisions (algorithm, access TTL, refresh TTL, rotation
policy, revocation strategy) documented with rationale.
Pass condition: Flutter storage location stated for both token types with security
justification.
Pass condition: Dio interceptor integration note describes the transparent refresh flow.
Pass condition: blast-radius test is written with named technical mechanisms at each step.
Pass condition: no sub-decision says "to be decided" or "we'll figure this out later."
