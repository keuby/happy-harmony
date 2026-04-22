// ArkTS facade over the nacl NAPI module. The underlying symbols throw on
// invalid input and return null on authentication failure; this wrapper
// keeps that contract so callers can pattern-match on `null` for auth
// failure without try/catch'ing non-failure paths.

import nacl from 'libnacl.so';

export const SECRETBOX_KEY_BYTES = 32;
export const SECRETBOX_NONCE_BYTES = 24;
export const SECRETBOX_MAC_BYTES = 16;

export function secretboxEasy(
  message: Uint8Array,
  nonce: Uint8Array,
  key: Uint8Array,
): Uint8Array {
  return nacl.secretboxEasy(message, nonce, key);
}

export function secretboxOpenEasy(
  ciphertext: Uint8Array,
  nonce: Uint8Array,
  key: Uint8Array,
): Uint8Array | null {
  return nacl.secretboxOpenEasy(ciphertext, nonce, key);
}
