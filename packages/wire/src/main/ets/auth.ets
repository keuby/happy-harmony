// Wire schemas for happy-server /v1/auth/* endpoints. Mirrors the Zod
// schemas defined on the happy-server side. Keep this file free of any
// app-internal types (Credentials, keypairs) — those live in service/auth
// on the consumer side; wire only carries what crosses the wire.

/** POST /v1/auth/account/request request body. */
export interface AuthRequestBody {
  /** base64 of the client's ephemeral X25519 public key. */
  publicKey: string;
}

/** POST /v1/auth/account/request response. */
export interface AuthRequestResponse {
  /** 'pending' | 'authorized'. Undefined means still pending. */
  state?: string;
  /** Opaque bearer token; only present when state === 'authorized'. */
  token?: string;
  /** base64 box bundle containing the 32-byte account secret. */
  response?: string;
}

/**
 * POST /v1/auth request body. Challenge-response login for a known
 * account: client proves ownership of the ed25519 key by signing a
 * random 32-byte challenge. Server returns a bearer token.
 */
export interface AuthLoginBody {
  /** base64 of ed25519 public key derived from the 32-byte account secret. */
  publicKey: string;
  /** base64 of the 32 random challenge bytes the client generated. */
  challenge: string;
  /** base64 of the 64-byte ed25519 signature over `challenge`. */
  signature: string;
}

/** POST /v1/auth response. */
export interface AuthLoginResponse {
  success: boolean;
  token: string;
}
