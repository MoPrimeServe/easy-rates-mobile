import { createHash, randomBytes, randomUUID } from "node:crypto";
import jwt from "jsonwebtoken";
import { ApiError } from "@easyrates/http";
import type { KvStore } from "./store.js";

/**
 * Token model (conventions §6):
 *  - Access token: RS256 JWT, 900s TTL, stateless (verified by public key).
 *  - Refresh token: opaque 256-bit hex, 30d TTL, SINGLE-USE, rotated on every
 *    refresh. Stored HASHED (SHA-256). Reuse of an already-rotated token is
 *    detected and revokes the entire familyId chain.
 *
 * Refresh state lives in the KvStore (Redis in dev) because the live Prisma
 * schema has no RefreshToken table (the auth plan flagged this as a schema gap)
 * and the schema is the migrated source of truth — adding a divergent table is
 * out of scope. Keys:
 *   refresh:{tokenHash}  → JSON { userId, familyId, status }  (TTL 30d)
 *   refreshfam:{familyId}→ "revoked"  (set on reuse-detection; TTL 30d)
 */

export interface TokenConfig {
  privateKeyPem: string;
  publicKeyPem: string;
  issuer: string;
  audience: string;
  accessTtlSeconds: number; // 900
  refreshTtlDays: number; // 30
  /**
   * Key id stamped into the access-token header (`kid`). Optional for back-compat;
   * when set, the JWKS published at `/.well-known/jwks.json` is usable by external
   * verifiers (they select the public key by this kid).
   */
  keyId?: string;
}

export interface AccessClaims {
  sub: string; // userId
  iss: string;
  aud: string;
  iat: number;
  exp: number;
}

export interface AuthTokenPair {
  userId: string;
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresInSeconds: number;
  refreshTokenTtlDays: number;
}

interface RefreshEntry {
  userId: string;
  familyId: string;
  status: "active" | "rotated";
}

function sha256Hex(s: string): string {
  return createHash("sha256").update(s).digest("hex");
}

export class TokenService {
  constructor(
    private readonly store: KvStore,
    private readonly cfg: TokenConfig,
  ) {}

  private get refreshTtlSeconds(): number {
    return this.cfg.refreshTtlDays * 24 * 60 * 60;
  }

  /** Sign a short-lived RS256 access token for `userId`. */
  signAccessToken(userId: string): string {
    return jwt.sign({}, this.cfg.privateKeyPem, {
      algorithm: "RS256",
      subject: userId,
      issuer: this.cfg.issuer,
      audience: this.cfg.audience,
      expiresIn: this.cfg.accessTtlSeconds,
      // Stamp the `kid` so a verifier can select the public key from the JWKS.
      ...(this.cfg.keyId ? { keyid: this.cfg.keyId } : {}),
    });
  }

  /** Verify an access token; throws ApiError.unauthenticated on any failure. */
  verifyAccessToken(token: string): AccessClaims {
    try {
      return jwt.verify(token, this.cfg.publicKeyPem, {
        algorithms: ["RS256"],
        issuer: this.cfg.issuer,
        audience: this.cfg.audience,
      }) as AccessClaims;
    } catch {
      throw ApiError.unauthenticated("Access token invalid or expired.");
    }
  }

  /** Mint a brand-new session token pair (new family). Used by register + verify(LOGIN). */
  async issueSession(userId: string): Promise<AuthTokenPair> {
    const familyId = randomUUID();
    return this.mintPair(userId, familyId);
  }

  private async mintPair(
    userId: string,
    familyId: string,
  ): Promise<AuthTokenPair> {
    const accessToken = this.signAccessToken(userId);
    const refreshToken = randomBytes(32).toString("hex"); // 256-bit
    const entry: RefreshEntry = { userId, familyId, status: "active" };
    await this.store.set(
      `refresh:${sha256Hex(refreshToken)}`,
      JSON.stringify(entry),
      this.refreshTtlSeconds,
    );
    return {
      userId,
      accessToken,
      refreshToken,
      accessTokenExpiresInSeconds: this.cfg.accessTtlSeconds,
      refreshTokenTtlDays: this.cfg.refreshTtlDays,
    };
  }

  /**
   * Rotate a refresh token. Single-use: the presented token is consumed and a
   * new pair issued in the same family. Reuse of an already-rotated token (or a
   * token whose family was revoked) revokes the whole family and 401s.
   */
  async refresh(refreshToken: string): Promise<AuthTokenPair> {
    const tokenHash = sha256Hex(refreshToken);
    const raw = await this.store.get(`refresh:${tokenHash}`);
    if (!raw) throw ApiError.unauthenticated("Refresh token invalid or expired.");

    const entry = JSON.parse(raw) as RefreshEntry;

    // Family already revoked? (a prior reuse tripped the alarm.)
    const famRevoked = await this.store.get(`refreshfam:${entry.familyId}`);
    if (famRevoked) {
      await this.store.del(`refresh:${tokenHash}`);
      throw ApiError.unauthenticated("Refresh token family revoked.");
    }

    // Reuse detection: a token already rotated must never be accepted again.
    if (entry.status === "rotated") {
      await this.revokeFamily(entry.familyId);
      throw ApiError.unauthenticated("Refresh token reuse detected.");
    }

    // Consume this token (mark rotated, keep it so a later reuse is detectable)…
    entry.status = "rotated";
    await this.store.set(
      `refresh:${tokenHash}`,
      JSON.stringify(entry),
      this.refreshTtlSeconds,
    );
    // …and mint a fresh pair in the same family.
    return this.mintPair(entry.userId, entry.familyId);
  }

  /** Revoke a single refresh token (logout). Idempotent. */
  async revoke(refreshToken: string): Promise<void> {
    await this.store.del(`refresh:${sha256Hex(refreshToken)}`);
  }

  /** Revoke an entire token family (reuse-detection blast radius). */
  async revokeFamily(familyId: string): Promise<void> {
    await this.store.set(
      `refreshfam:${familyId}`,
      "revoked",
      this.refreshTtlSeconds,
    );
  }
}

/**
 * Single-use registration proof token (otp/verify REGISTRATION → auth/register).
 * Opaque hex, short TTL, bound to the verified phone. Stored hashed in the
 * KvStore; consumed (deleted) by auth/register.
 */
export class RegistrationTokenService {
  constructor(
    private readonly store: KvStore,
    private readonly ttlSeconds: number,
  ) {}

  /** Mint a token bound to `phone`. Returns the opaque token to hand to the client. */
  async mint(phone: string): Promise<string> {
    const token = `rt_${randomBytes(24).toString("hex")}`;
    await this.store.set(
      `regtoken:${sha256Hex(token)}`,
      phone,
      this.ttlSeconds,
    );
    return token;
  }

  /**
   * Consume the token, asserting it is valid, unused, and matches `phone`.
   * Throws ApiError.unauthenticated on any mismatch (single-use).
   */
  async consume(token: string, phone: string): Promise<void> {
    const k = `regtoken:${sha256Hex(token)}`;
    const boundPhone = await this.store.get(k);
    if (!boundPhone || boundPhone !== phone) {
      throw ApiError.unauthenticated(
        "Registration token invalid, expired, or already used.",
      );
    }
    await this.store.del(k); // single-use
  }
}
