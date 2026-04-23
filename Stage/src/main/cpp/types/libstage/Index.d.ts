export const add: (a: number, b: number) => number;

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

export const cryptoBoxKeypair: () => KeyPair;
export const cryptoBoxKeypairFromSeed: (seed: Uint8Array) => KeyPair;
export const cryptoBoxEasy: (
  message: Uint8Array,
  nonce: Uint8Array,
  recipientPublicKey: Uint8Array,
  senderSecretKey: Uint8Array,
) => Uint8Array;
export const cryptoBoxOpenEasy: (
  ciphertext: Uint8Array,
  nonce: Uint8Array,
  senderPublicKey: Uint8Array,
  recipientSecretKey: Uint8Array,
) => Uint8Array | null;

export const cryptoSignKeypairFromSeed: (seed: Uint8Array) => KeyPair;
export const cryptoSignDetached: (
  message: Uint8Array,
  secretKey: Uint8Array,
) => Uint8Array;
export const cryptoSignVerifyDetached: (
  signature: Uint8Array,
  message: Uint8Array,
  publicKey: Uint8Array,
) => boolean;
