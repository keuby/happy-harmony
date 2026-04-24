// Challenge-response signature used for the secondary /v1/auth token
// refresh path. Not exercised by the 1a MVP flow but kept here so the
// sign-keypair + detached-sig NAPI surface has a real caller and
// there's an easy unit-test hook once 1b/1d lands.

import { cryptoSignDetached, cryptoSignKeypairFromSeed, randomBytes } from '../../common/crypto/libsodium';

export interface AuthChallenge {
  challenge: Uint8Array;
  signature: Uint8Array;
  publicKey: Uint8Array;
}

export function authChallenge(secret: Uint8Array): AuthChallenge {
  const kp = cryptoSignKeypairFromSeed(secret);
  const challenge = randomBytes(32);
  const signature = cryptoSignDetached(challenge, kp.secretKey);
  return { challenge, signature, publicKey: kp.publicKey };
}
