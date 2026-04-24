// Persistent credential store: {token, secret} blob shipped as JSON in
// @ohos.data.preferences. The happy-app analogue uses SecureStore (iOS
// Keychain / Android Keystore); preferences is sandboxed-but-plaintext.
// TODO(security): wrap the blob with a HUKS-derived key before shipping
// beyond development builds — tracked in docs/progress.md Phase 1a
// follow-ups. Scope-limited for MVP so auth flow ships sooner.

import preferences from '@ohos.data.preferences';
import type common from '@ohos.app.ability.common';

import { decodeBase64, encodeBase64 } from '../common/crypto/base64';

const STORE_NAME = 'happy_credentials';
const KEY_BLOB = 'credentials_json';

export interface Credentials {
  token: string;
  secret: Uint8Array;
}

interface StoredCredentials {
  token: string;
  secretBase64: string;
}

let handle: preferences.Preferences | null = null;

/**
 * Lazily open the preferences file backing the credential store.
 * @throws { BusinessError } 401 - Parameter error.
 * @throws { BusinessError } 15500000 - Inner error.
 */
export async function initCredentials(ctx: common.Context): Promise<void> {
  if (handle !== null) return;
  handle = await preferences.getPreferences(ctx, STORE_NAME);
}

function requireHandle(): preferences.Preferences {
  if (handle === null) throw new Error('credentials store not initialized');
  return handle;
}

/**
 * @returns { Promise<Credentials | null> } Stored credentials, or null if none.
 * @throws { BusinessError } 15500000 - Inner error.
 */
export async function loadCredentials(): Promise<Credentials | null> {
  const h = requireHandle();
  const raw = (await h.get(KEY_BLOB, '')) as string;
  if (raw === '') return null;
  const parsed = JSON.parse(raw) as StoredCredentials;
  return { token: parsed.token, secret: decodeBase64(parsed.secretBase64) };
}

/**
 * @throws { BusinessError } 401 - Parameter error.
 * @throws { BusinessError } 15500000 - Inner error.
 */
export async function saveCredentials(c: Credentials): Promise<void> {
  const h = requireHandle();
  const blob: StoredCredentials = { token: c.token, secretBase64: encodeBase64(c.secret) };
  await h.put(KEY_BLOB, JSON.stringify(blob));
  await h.flush();
}

/**
 * @throws { BusinessError } 15500000 - Inner error.
 */
export async function clearCredentials(): Promise<void> {
  const h = requireHandle();
  await h.delete(KEY_BLOB);
  await h.flush();
}
