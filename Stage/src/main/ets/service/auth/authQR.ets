// QR-code login wire. Mirrors sources/auth/authQRStart.ts and
// sources/auth/authQRWait.ts in happy-app.
//
// Flow:
//   1. generateAuthKeyPair() → random 32-byte seed, derive X25519 pair
//   2. authQRStart(pair) → POST /v1/auth/account/request with publicKey
//   3. authQRWait(pair) → poll same endpoint every 1 s until state is
//      'authorized'; decrypt response bundle to recover the 32-byte
//      account secret, return { token, secret }.

import { AuthRequestBody, AuthRequestResponse } from 'happy-wire';

import { decodeBase64, encodeBase64 } from '../../common/crypto/base64';
import { decryptBox } from '../../common/crypto/encryptBox';
import { KeyPair, cryptoBoxKeypairFromSeed, randomBytes } from '../../common/crypto/libsodium';
import { Credentials } from '../../storage/credentials';
import { ApiError, post } from '../../api/rest';

export interface AuthKeyPair {
  publicKey: Uint8Array;
  secretKey: Uint8Array;
}

const POLL_INTERVAL_MS = 1000;

/**
 * @throws { BusinessError } 401 - Parameter error.
 * @throws { BusinessError } 17620001 - Memory error.
 * @throws { BusinessError } 17620002 - Runtime error.
 */
export function generateAuthKeyPair(): AuthKeyPair {
  const seed = randomBytes(32);
  const kp: KeyPair = cryptoBoxKeypairFromSeed(seed);
  return { publicKey: kp.publicKey, secretKey: kp.secretKey };
}

export async function authQRStart(pair: AuthKeyPair): Promise<void> {
  const body: AuthRequestBody = { publicKey: encodeBase64(pair.publicKey) };
  await post<AuthRequestResponse>('/v1/auth/account/request', body);
}

/**
 * Poll the auth endpoint until the request is approved or the caller
 * asks to stop. Returns `null` if the caller cancels; throws ApiError
 * on network failure or malformed response.
 */
export async function authQRWait(
  pair: AuthKeyPair,
  shouldCancel: () => boolean,
): Promise<Credentials | null> {
  const body: AuthRequestBody = { publicKey: encodeBase64(pair.publicKey) };
  while (true) {
    if (shouldCancel()) return null;
    const resp = await post<AuthRequestResponse>('/v1/auth/account/request', body);
    if (resp.body.state === 'authorized') {
      const token = resp.body.token;
      const encryptedResp = resp.body.response;
      if (token === undefined || encryptedResp === undefined) {
        throw new ApiError('authQRWait: authorized response missing token/response', 0);
      }
      const bundle = decodeBase64(encryptedResp);
      const secret = decryptBox(bundle, pair.secretKey);
      if (secret === null) {
        throw new ApiError('authQRWait: failed to decrypt server response', 0);
      }
      return { token, secret };
    }
    await sleep(POLL_INTERVAL_MS, shouldCancel);
  }
}

async function sleep(ms: number, shouldCancel: () => boolean): Promise<void> {
  // Short-slice the wait so cancellation is observed within ~100 ms
  // rather than only at poll boundaries.
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (shouldCancel()) return;
    const remaining = end - Date.now();
    const step = Math.min(100, remaining);
    await new Promise<void>((resolve: () => void) => setTimeout(resolve, step));
  }
}
