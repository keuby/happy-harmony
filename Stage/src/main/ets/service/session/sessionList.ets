// Thin wrapper over GET /v1/sessions. Returns the raw wire array.
// Decryption (AES-256-GCM metadata / agentState) lands in PoC-A3; for now
// callers see the wire shape with ciphertext fields opaque.

import { Session, SessionListResponse } from 'happy-wire';

import { httpGet } from '../../api/rest';

export async function fetchSessions(): Promise<Session[]> {
  const resp = await httpGet<SessionListResponse>('/v1/sessions');
  return resp.body.sessions;
}
