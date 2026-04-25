// GET /v1/sessions with optional client-side metadata decrypt (PoC-A3).

import { Session, SessionListResponse } from 'happy-wire';

import { httpGet } from '../../api/rest';
import { DecryptedSession, SessionDecryptor } from './sessionDecrypt';

/** Raw wire array — leaves ciphertext fields opaque. */
export async function fetchSessions(): Promise<Session[]> {
  const resp = await httpGet<SessionListResponse>('/v1/sessions');
  return resp.body.sessions;
}

/**
 * Fetch + decrypt metadata in one shot. The decryptor is built per call
 * (2 HMAC-SHA512 + 1 box keygen, ~a few ms) so callers don't have to
 * hold one. Per-session failures degrade to `metadata: null`; they do
 * not fail the whole call.
 *
 * @throws { BusinessError } 401 - Parameter error.
 * @throws { BusinessError } 17620001 - Memory error.
 * @throws { BusinessError } 17620002 - Runtime error.
 * @throws { BusinessError } 17630001 - Crypto operation error.
 */
export async function fetchDecryptedSessions(masterSecret: Uint8Array): Promise<DecryptedSession[]> {
  const raw = await fetchSessions();
  const dec = await SessionDecryptor.create(masterSecret);
  const out: DecryptedSession[] = [];
  for (let i = 0; i < raw.length; i++) {
    out.push(await dec.decrypt(raw[i]));
  }
  return out;
}
