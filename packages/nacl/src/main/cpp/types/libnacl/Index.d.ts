// Type declarations for the nacl NAPI module.
// Surface mirrors the subset of libsodium used by happy auth + encryption.

export interface KeyPair {
  publicKey: Uint8Array;
  secretKey: Uint8Array;
}

/** Encrypt with XSalsa20-Poly1305. Returns [16-byte MAC || ciphertext]. */
export const secretboxEasy: (
  message: Uint8Array,
  nonce: Uint8Array,
  key: Uint8Array,
) => Uint8Array;

/**
 * Decrypt and verify XSalsa20-Poly1305. Input is [16-byte MAC || ciphertext].
 * Returns null on authentication failure.
 */
export const secretboxOpenEasy: (
  ciphertext: Uint8Array,
  nonce: Uint8Array,
  key: Uint8Array,
) => Uint8Array | null;

/** Generate a random X25519 keypair. */
export const cryptoBoxKeypair: () => KeyPair;

/** Derive an X25519 keypair deterministically from a 32-byte seed. */
export const cryptoBoxKeypairFromSeed: (seed: Uint8Array) => KeyPair;

/** Authenticated X25519+XSalsa20-Poly1305. Returns [16-byte MAC || ct]. */
export const cryptoBoxEasy: (
  message: Uint8Array,
  nonce: Uint8Array,
  recipientPublicKey: Uint8Array,
  senderSecretKey: Uint8Array,
) => Uint8Array;

/** Counterpart to cryptoBoxEasy. Returns null on authentication failure. */
export const cryptoBoxOpenEasy: (
  ciphertext: Uint8Array,
  nonce: Uint8Array,
  senderPublicKey: Uint8Array,
  recipientSecretKey: Uint8Array,
) => Uint8Array | null;

/** Derive an Ed25519 keypair deterministically from a 32-byte seed. */
export const cryptoSignKeypairFromSeed: (seed: Uint8Array) => KeyPair;

/** Produce a 64-byte Ed25519 detached signature. */
export const cryptoSignDetached: (
  message: Uint8Array,
  secretKey: Uint8Array,
) => Uint8Array;

/** Verify a 64-byte Ed25519 detached signature. */
export const cryptoSignVerifyDetached: (
  signature: Uint8Array,
  message: Uint8Array,
  publicKey: Uint8Array,
) => boolean;
