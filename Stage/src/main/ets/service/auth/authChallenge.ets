// Ed25519 challenge-response for POST /v1/auth self-service login.
// Mirrors happy-app/sources/auth/authChallenge.ts: derive the ed25519
// signing keypair from the 32-byte account secret and sign a fresh
// random challenge. Server verifies the signature against publicKey and
// issues a bearer token — no approver needed when the caller already
// holds the account secret (restore / DIY login flow).

import { cryptoSignDetached, cryptoSignKeypairFromSeed, randomBytes } from '../../common/crypto/libsodium';

export interface AuthChallenge {
  challenge: Uint8Array;
  signature: Uint8Array;
  publicKey: Uint8Array;
}

/**
 * @throws { BusinessError } 401 - Parameter error.
 * @throws { BusinessError } 17620001 - Memory error.
 * @throws { BusinessError } 17620002 - Runtime error.
 */
export function authChallenge(secret: Uint8Array): AuthChallenge {
  const kp = cryptoSignKeypairFromSeed(secret);
  const challenge = randomBytes(32);
  const signature = cryptoSignDetached(challenge, kp.secretKey);
  return { challenge, signature, publicKey: kp.publicKey };
}
