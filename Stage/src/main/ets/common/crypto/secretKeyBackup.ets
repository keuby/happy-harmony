// Parse account secret keys typed by the user back into 32 raw bytes.
// Mirrors happy-app/sources/auth/secretKeyBackup.ts but only the decode
// side: Stage never renders the secret, it only consumes one during
// Settings→Account restore. Keep the base32 alphabet and OCR-style
// substitutions (0→O, 1→I, 8→B, 9→G) byte-compatible with upstream so
// the same string round-trips.

import { decodeBase64 } from './base64';

const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function base32ToBytes(input: string): Uint8Array {
  const normalized = input.toUpperCase()
    .replace(/0/g, 'O')
    .replace(/1/g, 'I')
    .replace(/8/g, 'B')
    .replace(/9/g, 'G');
  const cleaned = normalized.replace(/[^A-Z2-7]/g, '');
  if (cleaned.length === 0) {
    throw new Error('secret key: no valid base32 characters found');
  }

  const out: number[] = [];
  let buffer = 0;
  let bits = 0;
  for (let i = 0; i < cleaned.length; i++) {
    const value = BASE32_ALPHABET.indexOf(cleaned.charAt(i));
    if (value === -1) {
      throw new Error('secret key: invalid base32 character');
    }
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.push((buffer >> bits) & 0xff);
    }
  }
  return new Uint8Array(out);
}

/**
 * Accepts either the formatted backup string (`XXXXX-XXXXX-...`, base32
 * with 5-char groups, possibly mistyped 0/1/8/9) or a plain base64 secret
 * and returns the raw 32-byte account secret. Throws on any length /
 * charset mismatch.
 */
export function normalizeSecretKey(input: string): Uint8Array {
  const trimmed = input.trim();
  if (trimmed === '') {
    throw new Error('secret key: empty input');
  }

  // Dashes, whitespace, or an over-long body are the tells for the
  // formatted base32 backup form. 32 bytes in base64 is 44 chars with
  // padding — anything beyond 50 is almost certainly the spaced backup.
  const looksFormatted = /[-\s]/.test(trimmed) || trimmed.length > 50;
  if (looksFormatted) {
    const bytes = base32ToBytes(trimmed);
    if (bytes.length !== 32) {
      throw new Error(`secret key: expected 32 bytes, got ${bytes.length}`);
    }
    return bytes;
  }

  // Fall back to base64. Accept base64url by normalizing `-_` → `+/`;
  // padding is optional for ArkTS' decoder but we add it back to be safe.
  let b64 = trimmed.replace(/-/g, '+').replace(/_/g, '/');
  const pad = b64.length % 4;
  if (pad === 2) b64 += '==';
  else if (pad === 3) b64 += '=';
  else if (pad === 1) {
    throw new Error('secret key: malformed base64 length');
  }
  try {
    const bytes = decodeBase64(b64);
    if (bytes.length !== 32) {
      throw new Error(`secret key: expected 32 bytes, got ${bytes.length}`);
    }
    return bytes;
  } catch (e) {
    // Last-ditch: maybe the user typed base32 without dashes. Try it.
    const bytes = base32ToBytes(trimmed);
    if (bytes.length !== 32) {
      throw new Error(`secret key: expected 32 bytes, got ${bytes.length}`);
    }
    return bytes;
  }
}
