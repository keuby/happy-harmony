// NaCl primitive wrappers backed by libnacl.so (built and shipped by
// the happy-nacl HAR). Stage imports the .so directly with a default
// import — happy-nacl HAR's main entry would re-wrap, but ohpm doesn't
// flow types transitively for that path under arkts strict, so we go
// straight to the typed .d.ts. `randomBytes` stays here because Stage
// prefers @ohos.security.cryptoFramework's RNG over the NAPI's own.

import nacl from 'libnacl.so';
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
 * Cryptographic random.
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
