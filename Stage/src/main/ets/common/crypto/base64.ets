// Standard base64 codec (RFC 4648, not URL-safe). Happy wire uses plain
// base64 for public keys, tokens, signatures — match upstream
// sources/encryption/base64.ts. If/when the server starts speaking
// base64url, gate behind a variant flag rather than changing the default.

import { util } from '@kit.ArkTS';

const helper = new util.Base64Helper();

export function encodeBase64(bytes: Uint8Array): string {
  return helper.encodeToStringSync(bytes);
}

export function decodeBase64(s: string): Uint8Array {
  return helper.decodeSync(s);
}

/**
 * URL-safe base64 (RFC 4648 §5): swap `+/` → `-_`, strip `=` padding.
 * The happy `happy:///account?...` auth-URL scheme expects this form.
 */
export function encodeBase64Url(bytes: Uint8Array): string {
  const s = helper.encodeToStringSync(bytes);
  return s.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
