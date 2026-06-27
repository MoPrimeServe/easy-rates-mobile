import { createPublicKey } from "node:crypto";

/**
 * KeyProvider — the signing-key boundary (plan 03 T11, the buildable half).
 *
 * Token signing and JWKS publication both go through this interface so the key
 * source is swappable. Two impls:
 *  - `EnvKeyProvider` — loads the RS256 PEMs already configured (env inline or
 *    a file path). The only impl that runs today.
 *  - `AzureKeyVaultKeyProvider` — a deliberately-unbuilt stub: real Key Vault
 *    integration needs provisioned infra (a Key Vault + managed identity), which
 *    is out of scope for this build. It throws on construction with a clear note.
 *
 * The published JWK is RS256/sig with a `kid` that MUST match the `kid` stamped
 * into the access-token header, so a verifier fetching `/.well-known/jwks.json`
 * can select the right key.
 */

/** A single RS256 public key as a JWK (RFC 7517), ready to publish in a JWK set. */
export interface PublicJwk {
  kid: string;
  kty: "RSA";
  use: "sig";
  alg: "RS256";
  n: string;
  e: string;
}

export interface Jwks {
  keys: PublicJwk[];
}

export interface SigningKey {
  /** The PEM the TokenService signs with (RS256 private key). */
  privateKeyPem: string;
  /** The key id to stamp into the JWT header (`kid`). */
  kid: string;
}

export interface KeyProvider {
  /** The current signing key (private PEM + kid) used to mint access tokens. */
  getSigningKey(): SigningKey;
  /** The public JWK set for verifiers (`GET /.well-known/jwks.json`). */
  getPublicJwks(): Jwks;
}

/**
 * Convert an RS256 public-key PEM into a published JWK. Node derives `kty/n/e`
 * from the key; we add the `kid`, and the fixed `use: "sig"` / `alg: "RS256"`.
 */
export function publicPemToJwk(publicKeyPem: string, kid: string): PublicJwk {
  const jwk = createPublicKey(publicKeyPem).export({ format: "jwk" }) as {
    kty?: string;
    n?: string;
    e?: string;
  };
  if (jwk.kty !== "RSA" || !jwk.n || !jwk.e) {
    throw new Error(
      "publicPemToJwk: expected an RSA public key PEM (RS256).",
    );
  }
  return { kid, kty: "RSA", use: "sig", alg: "RS256", n: jwk.n, e: jwk.e };
}

/** Env/file-backed KeyProvider — loads the RS256 dev PEMs. The buildable impl. */
export class EnvKeyProvider implements KeyProvider {
  private readonly jwks: Jwks;

  constructor(
    private readonly privateKeyPem: string,
    publicKeyPem: string,
    private readonly kid: string,
  ) {
    this.jwks = { keys: [publicPemToJwk(publicKeyPem, kid)] };
  }

  getSigningKey(): SigningKey {
    return { privateKeyPem: this.privateKeyPem, kid: this.kid };
  }

  getPublicJwks(): Jwks {
    return this.jwks;
  }
}

/**
 * Azure Key Vault KeyProvider — STUB. Real impl pulls the signing key (or a
 * signing operation) from a provisioned Key Vault via managed identity, and
 * publishes the Vault's public JWK. That requires infra that does not exist in
 * this environment, so this is intentionally unbuilt: it throws so a
 * misconfiguration (`JWT_KEY_PROVIDER=azure-key-vault`) fails loudly rather than
 * silently degrading.
 *
 * ⚠️ To build this: provision an Azure Key Vault, grant the service a managed
 * identity with key sign/get, then load the key here.
 */
export class AzureKeyVaultKeyProvider implements KeyProvider {
  constructor() {
    throw new Error(
      "AzureKeyVaultKeyProvider is not implemented — provision a Key Vault " +
        "(and a managed identity with key sign/get) first. Use JWT_KEY_PROVIDER=env for now.",
    );
  }

  getSigningKey(): SigningKey {
    throw new Error("AzureKeyVaultKeyProvider is not implemented.");
  }

  getPublicJwks(): Jwks {
    throw new Error("AzureKeyVaultKeyProvider is not implemented.");
  }
}
