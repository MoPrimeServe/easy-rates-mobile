/**
 * Bearer-auth middleware for auth-service.
 *
 * The implementation now lives in `@easyrates/auth-core` (`requireAuth`,
 * `AuthedRequest`) so property/bill/account reuse ONE copy. This file re-exports
 * it to keep auth-service's existing imports stable.
 */
export { requireAuth, type AuthedRequest } from "@easyrates/auth-core";
