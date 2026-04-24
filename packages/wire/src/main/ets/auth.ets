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
