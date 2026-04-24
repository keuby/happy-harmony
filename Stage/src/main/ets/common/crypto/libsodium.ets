// Re-export the NAPI-backed nacl surface from libstage.so with typed
// ArkTS wrappers. This keeps callers from importing 'libstage.so'
// directly so 1b can later swap the backing .so (or split into a HAR)
// without touching consumers.

import nacl from 'libstage.so';
import cryptoFramework from '@ohos.security.cryptoFramework';

export interface KeyPair {
  publicKey: Uint8Array;
  secretKey: Uint8Array;
}

export const SECRETBOX_KEY_BYTES = 32;
export const SECRETBOX_NONCE_BYTES = 24;
export const SECRETBOX_MAC_BYTES = 16;

export const BOX_PUBLIC_KEY_BYTES = 32;
export const BOX_SECRET_KEY_BYTES = 32;
export const BOX_NONCE_BYTES = 24;

export const SIGN_PUBLIC_KEY_BYTES = 32;
export const SIGN_SECRET_KEY_BYTES = 64;
export const SIGN_BYTES = 64;

export function secretboxEasy(message: Uint8Array, nonce: Uint8Array, key: Uint8Array): Uint8Array {
  return nacl.secretboxEasy(message, nonce, key);
}

export function secretboxOpenEasy(ciphertext: Uint8Array, nonce: Uint8Array, key: Uint8Array): Uint8Array | null {
  return nacl.secretboxOpenEasy(ciphertext, nonce, key);
}

export function cryptoBoxKeypair(): KeyPair {
  return nacl.cryptoBoxKeypair();
}

export function cryptoBoxKeypairFromSeed(seed: Uint8Array): KeyPair {
  return nacl.cryptoBoxKeypairFromSeed(seed);
}

export function cryptoBoxEasy(message: Uint8Array, nonce: Uint8Array, recipientPublicKey: Uint8Array, senderSecretKey: Uint8Array): Uint8Array {
  return nacl.cryptoBoxEasy(message, nonce, recipientPublicKey, senderSecretKey);
}

export function cryptoBoxOpenEasy(ciphertext: Uint8Array, nonce: Uint8Array, senderPublicKey: Uint8Array, recipientSecretKey: Uint8Array): Uint8Array | null {
  return nacl.cryptoBoxOpenEasy(ciphertext, nonce, senderPublicKey, recipientSecretKey);
}

export function cryptoSignKeypairFromSeed(seed: Uint8Array): KeyPair {
  return nacl.cryptoSignKeypairFromSeed(seed);
}

export function cryptoSignDetached(message: Uint8Array, secretKey: Uint8Array): Uint8Array {
  return nacl.cryptoSignDetached(message, secretKey);
}

export function cryptoSignVerifyDetached(signature: Uint8Array, message: Uint8Array, publicKey: Uint8Array): boolean {
  return nacl.cryptoSignVerifyDetached(signature, message, publicKey);
}

/**
 * Cryptographic random. @ohos.security.cryptoFramework.createRandom() is
 * the system-sanctioned entropy source; behind the scenes it reads
 * /dev/urandom just like the NAPI's own randombytes.c.
 *
 * @param { number } n - Number of random bytes to return.
 * @returns { Uint8Array } Random byte buffer of length n.
 * @throws { BusinessError } 401 - Parameter error.
 * @throws { BusinessError } 17620001 - Memory error.
 * @throws { BusinessError } 17620002 - Runtime error.
 */
export function randomBytes(n: number): Uint8Array {
  const rng = cryptoFramework.createRandom();
  const blob = rng.generateRandomSync(n);
  return new Uint8Array(blob.data);
}
