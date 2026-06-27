import { generateKeyPairSync } from "node:crypto";
import { describe, expect, it } from "vitest";
import {
  AzureKeyVaultKeyProvider,
  EnvKeyProvider,
  publicPemToJwk,
} from "./key-provider.js";

function rsaPair() {
  return generateKeyPairSync("rsa", {
    modulusLength: 2048,
    publicKeyEncoding: { type: "spki", format: "pem" },
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
  });
}

describe("publicPemToJwk — valid JWK shape", () => {
  it("emits a well-formed RS256 signing JWK", () => {
    const { publicKey } = rsaPair();
    const jwk = publicPemToJwk(publicKey, "kid-123");
    expect(jwk.kid).toBe("kid-123");
    expect(jwk.kty).toBe("RSA");
    expect(jwk.use).toBe("sig");
    expect(jwk.alg).toBe("RS256");
    // n and e are non-empty base64url strings.
    expect(typeof jwk.n).toBe("string");
    expect(jwk.n.length).toBeGreaterThan(0);
    expect(typeof jwk.e).toBe("string");
    expect(jwk.e.length).toBeGreaterThan(0);
    // base64url — no +, /, or = padding.
    expect(jwk.n).not.toMatch(/[+/=]/);
    expect(jwk.e).not.toMatch(/[+/=]/);
  });

  it("rejects a non-RSA key", () => {
    const { publicKey } = generateKeyPairSync("ed25519", {
      publicKeyEncoding: { type: "spki", format: "pem" },
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
    });
    expect(() => publicPemToJwk(publicKey, "kid")).toThrow(/RSA/);
  });
});

describe("EnvKeyProvider", () => {
  it("exposes the signing key with its kid", () => {
    const { publicKey, privateKey } = rsaPair();
    const kp = new EnvKeyProvider(privateKey, publicKey, "dev-kid");
    const signing = kp.getSigningKey();
    expect(signing.kid).toBe("dev-kid");
    expect(signing.privateKeyPem).toBe(privateKey);
  });

  it("publishes a single-key JWK set whose kid matches the signing kid", () => {
    const { publicKey, privateKey } = rsaPair();
    const kp = new EnvKeyProvider(privateKey, publicKey, "dev-kid");
    const jwks = kp.getPublicJwks();
    expect(jwks.keys).toHaveLength(1);
    const [jwk] = jwks.keys;
    expect(jwk!.kid).toBe("dev-kid");
    expect(jwk!.kty).toBe("RSA");
    expect(jwk!.use).toBe("sig");
    expect(jwk!.alg).toBe("RS256");
    expect(jwk!.kid).toBe(kp.getSigningKey().kid);
  });
});

describe("AzureKeyVaultKeyProvider — honest stub", () => {
  it("throws on construction (needs provisioned infra)", () => {
    expect(() => new AzureKeyVaultKeyProvider()).toThrow(/Key Vault/);
  });
});
