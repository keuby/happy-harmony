// ArkTS facade over the nacl NAPI module. The underlying symbols throw on
// invalid input and return null on authentication failure; this wrapper
// keeps that contract so callers can pattern-match on `null` for auth
// failure without try/catch'ing non-failure paths.

import nacl from 'libnacl.so';

export const SECRETBOX_KEY_BYTES = 32;
export const SECRETBOX_NONCE_BYTES = 24;
export const SECRETBOX_MAC_BYTES = 16;

export const BOX_PUBLIC_KEY_BYTES = 32;
export const BOX_SECRET_KEY_BYTES = 32;
export const BOX_NONCE_BYTES = 24;
export const BOX_MAC_BYTES = 16;
export const BOX_SEED_BYTES = 32;

export const SIGN_PUBLIC_KEY_BYTES = 32;
export const SIGN_SECRET_KEY_BYTES = 64;
export const SIGN_BYTES = 64;
export const SIGN_SEED_BYTES = 32;

export interface KeyPair {
  publicKey: Uint8Array;
  secretKey: Uint8Array;
}

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

export function cryptoBoxKeypair(): KeyPair {
  return nacl.cryptoBoxKeypair();
}

export function cryptoBoxKeypairFromSeed(seed: Uint8Array): KeyPair {
  return nacl.cryptoBoxKeypairFromSeed(seed);
}

export function cryptoBoxEasy(
  message: Uint8Array,
  nonce: Uint8Array,
  recipientPublicKey: Uint8Array,
  senderSecretKey: Uint8Array,
): Uint8Array {
  return nacl.cryptoBoxEasy(message, nonce, recipientPublicKey, senderSecretKey);
}

export function cryptoBoxOpenEasy(
  ciphertext: Uint8Array,
  nonce: Uint8Array,
  senderPublicKey: Uint8Array,
  recipientSecretKey: Uint8Array,
): Uint8Array | null {
  return nacl.cryptoBoxOpenEasy(ciphertext, nonce, senderPublicKey, recipientSecretKey);
}

export function cryptoSignKeypairFromSeed(seed: Uint8Array): KeyPair {
  return nacl.cryptoSignKeypairFromSeed(seed);
}

export function cryptoSignDetached(
  message: Uint8Array,
  secretKey: Uint8Array,
): Uint8Array {
  return nacl.cryptoSignDetached(message, secretKey);
}

export function cryptoSignVerifyDetached(
  signature: Uint8Array,
  message: Uint8Array,
  publicKey: Uint8Array,
): boolean {
  return nacl.cryptoSignVerifyDetached(signature, message, publicKey);
}
