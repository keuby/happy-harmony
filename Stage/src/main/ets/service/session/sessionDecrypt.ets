// Decrypt session metadata / agentState into view-friendly models.
// Mirrors happy-app's sync/encryption/encryption.ts + sessionEncryption.ts,
// but trimmed to what Stage's read-only session list needs today.
//
// Flow (V2 AES-GCM path — see PoC-A3 notes in docs/progress.md):
//   1. masterSecret → contentDataKey via HMAC-SHA512 tree
//        deriveKey(masterSecret, 'Happy EnCoder', ['content'])
//   2. contentKeyPair = crypto_box_seed_keypair(contentDataKey)  (X25519)
//   3. Per session: dataEncryptionKey wire is
//        0x00 || ephemeralPubKey(32) || nonce(24) || crypto_box_easy(32-byte dataKey)
//      Unpack and crypto_box_open_easy with contentKeyPair.secretKey → dataKey.
//   4. metadata wire is 0x00 || iv(12) || ciphertext || tag(16); AES-GCM
//      decrypt with dataKey → JSON plaintext → Metadata.
//
// V1 legacy path (dataEncryptionKey === null): wire is plain NaCl
// secretbox `nonce(24) || mac(16) || ciphertext`, opened with masterSecret
// directly. None of the current real-device sessions exercise V1 but we
// keep the branch for parity with upstream.

import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

import { Session } from 'happy-wire';

import {
  KeyPair,
  cryptoBoxKeypairFromSeed,
  cryptoBoxOpenEasy,
  secretboxOpenEasy,
} from '../../common/crypto/libsodium';
import { deriveKey } from '../../common/crypto/deriveKey';
import { decryptAes256Gcm } from '../../common/crypto/aesGcm';
import { decodeBase64 } from '../../common/crypto/base64';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'sessionDecrypt';

const utf8Decoder = util.TextDecoder.create('utf-8');

const BOX_PK_BYTES = 32;
const BOX_NONCE_BYTES = 24;
const SECRETBOX_NONCE_BYTES = 24;

/**
 * Subset of happy's Metadata schema (storageTypes.ts) that the harmony
 * UI actually renders today. Grow as Phase 2 pages need more fields —
 * unknown fields in the decoded JSON are silently ignored.
 */
export interface SessionMetadata {
  path: string;
  host: string;
  summaryText?: string;
  name?: string;
  os?: string;
}

export interface DecryptedSession {
  session: Session;
  metadata: SessionMetadata | null;
}

/**
 * Builds once from masterSecret (~2 HMAC-SHA512 + 1 NaCl keygen) and
 * reuses the contentKeyPair for every session decrypt.
 */
export class SessionDecryptor {
  private readonly masterSecret: Uint8Array;
  private readonly contentKeyPair: KeyPair;

  private constructor(masterSecret: Uint8Array, contentKeyPair: KeyPair) {
    this.masterSecret = masterSecret;
    this.contentKeyPair = contentKeyPair;
  }

  /**
   * @throws { BusinessError } 401 - Parameter error.
   * @throws { BusinessError } 17620001 - Memory error.
   * @throws { BusinessError } 17620002 - Runtime error.
   * @throws { BusinessError } 17630001 - Crypto operation error.
   */
  static async create(masterSecret: Uint8Array): Promise<SessionDecryptor> {
    const contentDataKey = await deriveKey(masterSecret, 'Happy EnCoder', ['content']);
    const contentKeyPair = cryptoBoxKeypairFromSeed(contentDataKey);
    return new SessionDecryptor(masterSecret, contentKeyPair);
  }

  async decrypt(session: Session): Promise<DecryptedSession> {
    try {
      const metadata = await this.decryptMetadata(session);
      return { session, metadata };
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'decrypt %{public}s failed: %{public}s',
        session.id, e instanceof Error ? e.message : JSON.stringify(e));
      return { session, metadata: null };
    }
  }

  /**
   * @throws { BusinessError } 17620001 - Memory error.
   * @throws { BusinessError } 17620002 - Runtime error.
   * @throws { BusinessError } 17630001 - Crypto operation error (auth-tag mismatch, bad key).
   * @throws { Error } on malformed bundle layout (see decryptAes256Gcm).
   */
  private async decryptMetadata(session: Session): Promise<SessionMetadata | null> {
    const mdBytes = decodeBase64(session.metadata);
    let plaintext: Uint8Array | null;
    if (session.dataEncryptionKey === null) {
      plaintext = this.openLegacyMetadata(mdBytes);
    } else {
      const dataKey = this.unwrapDataKey(decodeBase64(session.dataEncryptionKey));
      if (dataKey === null) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'dataKey unwrap failed for %{public}s', session.id);
        return null;
      }
      plaintext = await decryptAes256Gcm(mdBytes, dataKey);
    }
    if (plaintext === null) return null;
    const json = utf8Decoder.decodeToString(plaintext);
    return parseMetadata(json);
  }

  private unwrapDataKey(bundle: Uint8Array): Uint8Array | null {
    // 0x00 || ephPk(32) || nonce(24) || crypto_box_easy body
    if (bundle.length < 1 + BOX_PK_BYTES + BOX_NONCE_BYTES) return null;
    if (bundle[0] !== 0) return null;
    const ephPub = bundle.slice(1, 1 + BOX_PK_BYTES);
    const nonce = bundle.slice(1 + BOX_PK_BYTES, 1 + BOX_PK_BYTES + BOX_NONCE_BYTES);
    const body = bundle.slice(1 + BOX_PK_BYTES + BOX_NONCE_BYTES);
    return cryptoBoxOpenEasy(body, nonce, ephPub, this.contentKeyPair.secretKey);
  }

  private openLegacyMetadata(bundle: Uint8Array): Uint8Array | null {
    if (bundle.length < SECRETBOX_NONCE_BYTES) return null;
    const nonce = bundle.slice(0, SECRETBOX_NONCE_BYTES);
    const ct = bundle.slice(SECRETBOX_NONCE_BYTES);
    return secretboxOpenEasy(ct, nonce, this.masterSecret);
  }
}

interface MetadataWire {
  path?: string;
  host?: string;
  name?: string;
  os?: string;
  summary?: SummaryWire;
}

interface SummaryWire {
  text?: string;
}

function parseMetadata(json: string): SessionMetadata | null {
  try {
    const obj = JSON.parse(json) as MetadataWire;
    if (typeof obj.path !== 'string' || typeof obj.host !== 'string') return null;
    const md: SessionMetadata = { path: obj.path, host: obj.host };
    if (typeof obj.name === 'string') md.name = obj.name;
    if (typeof obj.os === 'string') md.os = obj.os;
    if (obj.summary !== undefined && typeof obj.summary.text === 'string') {
      md.summaryText = obj.summary.text;
    }
    return md;
  } catch (e) {
    return null;
  }
}
