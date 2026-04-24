// encryptBox / decryptBox wire format, exactly matching
// sources/encryption/libsodium.ts in happy-app:
//
//   bundle = [ephemeralPublicKey(32) || nonce(24) || ciphertext(n+16)]
//
// Encrypt side creates an ephemeral X25519 keypair, uses its secret key
// to seal the message to the recipient's public key, and throws away
// the ephemeral secret. Decrypt side uses the embedded ephemeral public
// key to open the box with its own long-term secret key.

import {
  BOX_NONCE_BYTES,
  BOX_PUBLIC_KEY_BYTES,
  cryptoBoxEasy,
  cryptoBoxKeypair,
  cryptoBoxOpenEasy,
  randomBytes,
} from './libsodium';

/**
 * @throws { BusinessError } 401 - Parameter error.
 * @throws { BusinessError } 17620001 - Memory error.
 * @throws { BusinessError } 17620002 - Runtime error.
 */
export function encryptBox(data: Uint8Array, recipientPublicKey: Uint8Array): Uint8Array {
  const ephemeral = cryptoBoxKeypair();
  const nonce = randomBytes(BOX_NONCE_BYTES);
  const ct = cryptoBoxEasy(data, nonce, recipientPublicKey, ephemeral.secretKey);
  const out = new Uint8Array(ephemeral.publicKey.length + nonce.length + ct.length);
  out.set(ephemeral.publicKey, 0);
  out.set(nonce, ephemeral.publicKey.length);
  out.set(ct, ephemeral.publicKey.length + nonce.length);
  return out;
}

export function decryptBox(bundle: Uint8Array, recipientSecretKey: Uint8Array): Uint8Array | null {
  if (bundle.length < BOX_PUBLIC_KEY_BYTES + BOX_NONCE_BYTES) return null;
  const ephemeralPk = bundle.slice(0, BOX_PUBLIC_KEY_BYTES);
  const nonce = bundle.slice(BOX_PUBLIC_KEY_BYTES, BOX_PUBLIC_KEY_BYTES + BOX_NONCE_BYTES);
  const ct = bundle.slice(BOX_PUBLIC_KEY_BYTES + BOX_NONCE_BYTES);
  return cryptoBoxOpenEasy(ct, nonce, ephemeralPk, recipientSecretKey);
}
