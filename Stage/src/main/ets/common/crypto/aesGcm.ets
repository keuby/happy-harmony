// AES-256-GCM decryption via @ohos.security.cryptoFramework.
//
// Wire layout consumed by happy-server's session.metadata /
// session.agentState fields:
//
//   0x00 || iv(12) || ciphertext || tag(16)
//
// (The 0x00 prefix is `rn-encryption`'s version byte — see
// sources/sync/encryption/encryptor.ts:AES256Encryption. Upstream's JCE
// doFinal appends the tag to the ciphertext implicitly; cryptoFramework
// on HarmonyOS takes tag via GcmParamsSpec, so we split here.)

import cryptoFramework from '@ohos.security.cryptoFramework';

const IV_BYTES = 12;
const TAG_BYTES = 16;
const VERSION_BYTE = 0x00;

/**
 * Decrypt the `0x00 || iv || ct || tag` bundle with a raw 32-byte AES-256
 * key. Returns the plaintext bytes; throws on auth-tag mismatch or any
 * malformed input. Callers that want a null-on-failure contract should
 * try/catch at the call site.
 *
 * @throws { Error } on version-byte mismatch or too-short bundle.
 * @throws { BusinessError } 17620001 - Memory error.
 * @throws { BusinessError } 17620002 - Runtime error.
 * @throws { BusinessError } 17630001 - Crypto operation error (bad tag, bad key).
 */
export async function decryptAes256Gcm(bundle: Uint8Array, key: Uint8Array): Promise<Uint8Array> {
  if (bundle.length < 1 + IV_BYTES + TAG_BYTES) {
    throw new Error(`aes-gcm: bundle too short (${bundle.length} bytes)`);
  }
  if (bundle[0] !== VERSION_BYTE) {
    throw new Error(`aes-gcm: unexpected version byte 0x${bundle[0].toString(16)}`);
  }
  if (key.length !== 32) {
    throw new Error(`aes-gcm: expected 32-byte key, got ${key.length}`);
  }

  const iv = bundle.slice(1, 1 + IV_BYTES);
  const ct = bundle.slice(1 + IV_BYTES, bundle.length - TAG_BYTES);
  const tag = bundle.slice(bundle.length - TAG_BYTES);

  const symKeyGen = cryptoFramework.createSymKeyGenerator('AES256');
  const symKey = await symKeyGen.convertKey({ data: key } as cryptoFramework.DataBlob);

  const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
  const params: cryptoFramework.GcmParamsSpec = {
    iv: { data: iv },
    authTag: { data: tag },
    aad: { data: new Uint8Array(0) },
    algName: 'GcmParamsSpec',
  };
  await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
  const plain = await cipher.doFinal({ data: ct } as cryptoFramework.DataBlob);
  return new Uint8Array(plain.data);
}
