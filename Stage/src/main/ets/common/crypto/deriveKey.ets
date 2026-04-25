// BIP32-style key tree derivation. Mirrors
// happy-app/sources/encryption/deriveKey.ts — root takes a usage tag
// ("<usage> Master Seed"), children take index strings with a 0x00
// separator byte prepended. HMAC-SHA512's output is split key/chainCode
// 32/32. Used to derive contentDataKey from the account master secret.

import { util } from '@kit.ArkTS';

import { hmacSha512 } from './hmacSha512';

const utf8 = util.TextEncoder.create('utf-8');

export interface KeyTreeState {
  key: Uint8Array;
  chainCode: Uint8Array;
}

/**
 * @throws { BusinessError } 17630001 - HMAC error.
 */
export async function deriveSecretKeyTreeRoot(seed: Uint8Array, usage: string): Promise<KeyTreeState> {
  const tag = utf8.encodeInto(`${usage} Master Seed`);
  const I = await hmacSha512(tag, seed);
  return { key: I.slice(0, 32), chainCode: I.slice(32) };
}

/**
 * @throws { BusinessError } 17630001 - HMAC error.
 */
export async function deriveSecretKeyTreeChild(chainCode: Uint8Array, index: string): Promise<KeyTreeState> {
  const indexBytes = utf8.encodeInto(index);
  const data = new Uint8Array(1 + indexBytes.length);
  data[0] = 0;
  data.set(indexBytes, 1);
  const I = await hmacSha512(chainCode, data);
  return { key: I.slice(0, 32), chainCode: I.slice(32) };
}

/**
 * Walk the tree: root(seed, usage) → child(chainCode, path[0]) → …
 * @returns { Promise<Uint8Array> } 32-byte leaf key.
 * @throws { BusinessError } 17630001 - HMAC error.
 */
export async function deriveKey(master: Uint8Array, usage: string, path: string[]): Promise<Uint8Array> {
  let state = await deriveSecretKeyTreeRoot(master, usage);
  for (let i = 0; i < path.length; i++) {
    state = await deriveSecretKeyTreeChild(state.chainCode, path[i]);
  }
  return state.key;
}
