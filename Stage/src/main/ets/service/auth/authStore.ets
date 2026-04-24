// Observable auth state + operations.
//
// Lifecycle:
//   loading → unauthenticated        no persisted credentials
//   loading → authenticated          persisted credentials found
//   unauthenticated → authenticating user tapped Connect
//   authenticating → authenticated   QR approval + decrypt succeeded
//   authenticating → unauthenticated user tapped Cancel, or error
//   authenticated → unauthenticated  user tapped Logout
//
// Single module-level instance; Index.ets binds it via @State and passes
// it to the two pages. Mutations happen only through the exported
// functions in this file — pages should never write store.* directly.

import { hilog } from '@kit.PerformanceAnalysisKit';
import type common from '@ohos.app.ability.common';

import {
  AuthKeyPair,
  authQRStart,
  authQRWait,
  generateAuthKeyPair,
} from './authQR';
import {
  Credentials,
  clearCredentials,
  initCredentials,
  loadCredentials,
  saveCredentials,
} from '../../storage/credentials';
import { clearBearerToken, setBearerToken } from '../../api/rest';
import { encodeBase64, encodeBase64Url } from '../../common/crypto/base64';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'authStore';

// Dev bootstrap: when non-empty, initAuth short-circuits the QR flow and
// writes these values straight into the credential store on first launch.
// Used for local end-to-end testing against a self-hosted happy-server.
// MUST stay '' on main. Paste a dev token from dev-secrets.local.json5
// (gitignored) only for local runs, then revert before committing.
const DEV_TOKEN: string = '';

export type AuthStatus = 'loading' | 'unauthenticated' | 'authenticating' | 'authenticated';

@Observed
export class AuthState {
  status: AuthStatus = 'loading';
  /** Full `happy:///account?<base64url>` URL the approver pastes/scans. Populated while status === 'authenticating'. */
  pendingPublicKey: string = '';
  /** error message from the last failed login attempt. Cleared when a new attempt starts. */
  lastError: string = '';
  /** base64 account secret after successful login. Empty string otherwise. */
  secretBase64: string = '';
  /** auth token after successful login. Empty string otherwise. */
  token: string = '';
}

export const authStore = new AuthState();

let currentKeyPair: AuthKeyPair | null = null;
let cancelRequested = false;

export async function initAuth(ctx: common.Context): Promise<void> {
  try {
    await initCredentials(ctx);
    const saved = await loadCredentials();
    if (saved !== null) {
      applyAuthenticated(saved);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'restored credentials from storage');
    } else if (DEV_TOKEN !== '') {
      const devCreds: Credentials = { token: DEV_TOKEN, secret: new Uint8Array(32) };
      await saveCredentials(devCreds);
      applyAuthenticated(devCreds);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'dev bootstrap: injected DEV_TOKEN credentials');
    } else {
      authStore.status = 'unauthenticated';
      hilog.info(LOG_DOMAIN, LOG_TAG, 'no stored credentials; awaiting login');
    }
  } catch (e) {
    authStore.status = 'unauthenticated';
    authStore.lastError = `init failed: ${JSON.stringify(e)}`;
    hilog.error(LOG_DOMAIN, LOG_TAG, 'init error: %{public}s', JSON.stringify(e));
  }
}

/**
 * Kick off QR login. Fires async; the UI reads `authStore.status` /
 * `pendingPublicKey` to react. Safe to call only from the
 * 'unauthenticated' state.
 *
 * @throws { BusinessError } 401 - Parameter error.
 * @throws { BusinessError } 17620001 - Memory error.
 * @throws { BusinessError } 17620002 - Runtime error.
 */
export function startLogin(): void {
  if (authStore.status !== 'unauthenticated') return;
  authStore.lastError = '';
  const pair = generateAuthKeyPair();
  currentKeyPair = pair;
  cancelRequested = false;
  authStore.pendingPublicKey = `happy:///account?${encodeBase64Url(pair.publicKey)}`;
  authStore.status = 'authenticating';
  hilog.info(LOG_DOMAIN, LOG_TAG, 'login started: url=%{public}s', authStore.pendingPublicKey);

  void runLogin(pair);
}

async function runLogin(pair: AuthKeyPair): Promise<void> {
  try {
    await authQRStart(pair);
    const creds = await authQRWait(pair, () => cancelRequested);
    if (creds === null) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'login cancelled by user');
      return;
    }
    await saveCredentials(creds);
    applyAuthenticated(creds);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'login complete; token=%{public}s...', creds.token.substring(0, 8));
  } catch (e) {
    if (authStore.status === 'authenticating') {
      authStore.status = 'unauthenticated';
      authStore.pendingPublicKey = '';
      authStore.lastError = `login failed: ${JSON.stringify(e)}`;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'login error: %{public}s', JSON.stringify(e));
    }
  } finally {
    currentKeyPair = null;
  }
}

export function cancelLogin(): void {
  if (authStore.status !== 'authenticating') return;
  cancelRequested = true;
  authStore.status = 'unauthenticated';
  authStore.pendingPublicKey = '';
  hilog.info(LOG_DOMAIN, LOG_TAG, 'cancel requested');
}

export async function logout(): Promise<void> {
  try {
    await clearCredentials();
  } catch (e) {
    hilog.error(LOG_DOMAIN, LOG_TAG, 'clearCredentials failed: %{public}s', JSON.stringify(e));
  }
  clearBearerToken();
  authStore.token = '';
  authStore.secretBase64 = '';
  authStore.pendingPublicKey = '';
  authStore.lastError = '';
  authStore.status = 'unauthenticated';
  hilog.info(LOG_DOMAIN, LOG_TAG, 'logged out');
}

function applyAuthenticated(c: Credentials): void {
  setBearerToken(c.token);
  authStore.token = c.token;
  authStore.secretBase64 = encodeBase64(c.secret);
  authStore.pendingPublicKey = '';
  authStore.lastError = '';
  authStore.status = 'authenticated';
}
