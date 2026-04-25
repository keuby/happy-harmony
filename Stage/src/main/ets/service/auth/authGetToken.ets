// POST /v1/auth: sign a random challenge with the ed25519 key derived
// from the account secret, receive a bearer token in return. Mirrors
// happy-app/sources/auth/authGetToken.ts.

import { AuthLoginBody, AuthLoginResponse } from 'happy-wire';

import { ApiError, post } from '../../api/rest';
import { encodeBase64 } from '../../common/crypto/base64';
import { authChallenge } from './authChallenge';

/**
 * @throws { ApiError } on non-2xx / network error / empty response.
 */
export async function authGetToken(secret: Uint8Array): Promise<string> {
  const c = authChallenge(secret);
  const body: AuthLoginBody = {
    publicKey: encodeBase64(c.publicKey),
    challenge: encodeBase64(c.challenge),
    signature: encodeBase64(c.signature),
  };
  const resp = await post<AuthLoginResponse>('/v1/auth', body);
  if (resp.body.token === undefined || resp.body.token === '') {
    throw new ApiError('authGetToken: server omitted token', resp.status);
  }
  return resp.body.token;
}
