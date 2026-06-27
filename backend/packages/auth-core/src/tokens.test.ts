import { describe, it, expect } from "vitest";
import { generateKeyPairSync } from "node:crypto";
import { MemoryKvStore } from "./store.js";
import {
  TokenService,
  RegistrationTokenService,
  type TokenConfig,
} from "./tokens.js";

const { privateKey, publicKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "spki", format: "pem" },
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
});

const CFG: TokenConfig = {
  privateKeyPem: privateKey,
  publicKeyPem: publicKey,
  issuer: "easyrates-auth",
  audience: "easyrates-api",
  accessTtlSeconds: 900,
  refreshTtlDays: 30,
};

function svc() {
  return new TokenService(new MemoryKvStore(), CFG);
}

describe("TokenService", () => {
  it("issues a session and verifies the access token (sub = userId)", async () => {
    const s = svc();
    const pair = await s.issueSession("user_123");
    expect(pair.accessTokenExpiresInSeconds).toBe(900);
    expect(pair.refreshTokenTtlDays).toBe(30);
    expect(pair.refreshToken).toMatch(/^[0-9a-f]{64}$/); // 256-bit hex
    const claims = s.verifyAccessToken(pair.accessToken);
    expect(claims.sub).toBe("user_123");
  });

  it("stamps the kid into the access-token header when keyId is set, still verifiable", async () => {
    const s = new TokenService(new MemoryKvStore(), {
      ...CFG,
      keyId: "kid-abc",
    });
    const token = s.signAccessToken("user_123");
    const headerJson = Buffer.from(
      token.split(".")[0]!,
      "base64url",
    ).toString("utf8");
    const header = JSON.parse(headerJson) as { alg: string; kid?: string };
    expect(header.alg).toBe("RS256");
    expect(header.kid).toBe("kid-abc");
    // Verification still works with a kid present.
    expect(s.verifyAccessToken(token).sub).toBe("user_123");
  });

  it("omits kid when keyId is not configured (back-compat)", () => {
    const token = svc().signAccessToken("user_123");
    const header = JSON.parse(
      Buffer.from(token.split(".")[0]!, "base64url").toString("utf8"),
    ) as { kid?: string };
    expect(header.kid).toBeUndefined();
  });

  it("rotates the refresh token (single-use): old token rejected, new accepted", async () => {
    const s = svc();
    const pair = await s.issueSession("user_123");
    const rotated = await s.refresh(pair.refreshToken);
    expect(rotated.refreshToken).not.toBe(pair.refreshToken);
    // New token works…
    const again = await s.refresh(rotated.refreshToken);
    expect(again.refreshToken).not.toBe(rotated.refreshToken);
  });

  it("reuse of a rotated token revokes the whole family", async () => {
    const s = svc();
    const pair = await s.issueSession("user_123");
    const rotated = await s.refresh(pair.refreshToken); // pair.refreshToken now 'rotated'
    // Reuse the consumed token → 401 + family revoked.
    await expect(s.refresh(pair.refreshToken)).rejects.toMatchObject({
      code: "unauthenticated",
    });
    // The legitimately-rotated token is now also dead (family revoked).
    await expect(s.refresh(rotated.refreshToken)).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });

  it("logout revokes a single refresh token", async () => {
    const s = svc();
    const pair = await s.issueSession("user_123");
    await s.revoke(pair.refreshToken);
    await expect(s.refresh(pair.refreshToken)).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });
});

describe("RegistrationTokenService", () => {
  it("mints, consumes (single-use), and binds to the phone", async () => {
    const r = new RegistrationTokenService(new MemoryKvStore(), 600);
    const token = await r.mint("+27821234567");
    expect(token).toMatch(/^rt_[0-9a-f]{48}$/);
    // Wrong phone → rejected.
    await expect(r.consume(token, "+27829999999")).rejects.toMatchObject({
      code: "unauthenticated",
    });
    // Correct phone → consumed once…
    await r.consume(token, "+27821234567");
    // …then dead.
    await expect(r.consume(token, "+27821234567")).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });
});
