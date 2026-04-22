// Type declarations for the nacl NAPI module.
// PoC-A2 surface: secretbox_easy / secretbox_open_easy only.

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
