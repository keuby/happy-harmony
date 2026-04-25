// HMAC-SHA512 via @ohos.security.cryptoFramework. Promise-based to match
// happy-app's hmac_sha512 contract. Used by deriveKey's BIP32-style key
// tree (see deriveKey.ets).

import cryptoFramework from '@ohos.security.cryptoFramework';

/**
 * @param { Uint8Array } key - HMAC key; any length accepted.
 * @param { Uint8Array } data - Message bytes.
 * @returns { Promise<Uint8Array> } 64-byte HMAC-SHA512 digest.
 * @throws { BusinessError } 401 - Parameter error.
 * @throws { BusinessError } 17620001 - Memory error.
 * @throws { BusinessError } 17620002 - Runtime error.
 * @throws { BusinessError } 17630001 - Crypto operation error.
 */
export async function hmacSha512(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const keyBlob: cryptoFramework.DataBlob = { data: key };
  const symKeyGen = cryptoFramework.createSymKeyGenerator('HMAC');
  const symKey = await symKeyGen.convertKey(keyBlob);

  const mac = cryptoFramework.createMac('SHA512');
  await mac.init(symKey);
  await mac.update({ data: data } as cryptoFramework.DataBlob);
  const out = await mac.doFinal();
  return new Uint8Array(out.data);
}
