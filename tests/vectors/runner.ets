// On-device test runner for PoC-A2. Drop this into a HarmonyOS entry
// module's pages/ (or call it from a button handler) to verify that
// libnacl.z.so on the target device produces byte-identical output to
// the reference tweetnacl-js used by happy-agent.
//
// Reads secretbox.json from rawfile resources, runs every vector through
// secretboxEasy / secretboxOpenEasy, and reports mismatches.

import { secretboxEasy, secretboxOpenEasy } from '@ohos/nacl';
import { resourceManager } from '@kit.LocalizationKit';

interface Vector {
  name: string;
  plaintextHex: string;
  nonceHex: string;
  keyHex: string;
  ciphertextHex: string;
  plaintextLen: number;
  ciphertextLen: number;
}

interface Mutated {
  name: string;
  ciphertextHex: string;
  nonceHex: string;
  keyHex: string;
}

interface Fixtures {
  generator: string;
  generatedAt: string;
  vectors: Vector[];
  mutated: Mutated[];
}

function hexToU8(hex: string): Uint8Array {
  const len = hex.length / 2;
  const out = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    out[i] = parseInt(hex.substr(i * 2, 2), 16);
  }
  return out;
}

function u8ToHex(u8: Uint8Array): string {
  let s = '';
  for (let i = 0; i < u8.length; i++) {
    s += u8[i].toString(16).padStart(2, '0');
  }
  return s;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

export interface TestReport {
  total: number;
  passed: number;
  failed: string[];
}

export async function runSecretboxVectors(rm: resourceManager.ResourceManager): Promise<TestReport> {
  const raw = await rm.getRawFileContent('secretbox.json');
  const text = new TextDecoder().decode(raw);
  const fx = JSON.parse(text) as Fixtures;

  const failed: string[] = [];
  let total = 0;

  for (const v of fx.vectors) {
    total += 2;
    const pt = hexToU8(v.plaintextHex);
    const n = hexToU8(v.nonceHex);
    const k = hexToU8(v.keyHex);
    const expectedCt = hexToU8(v.ciphertextHex);

    // Encrypt forward.
    const ct = secretboxEasy(pt, n, k);
    if (!bytesEqual(ct, expectedCt)) {
      failed.push(`${v.name} encrypt: got ${u8ToHex(ct)}, expected ${v.ciphertextHex}`);
    }

    // Decrypt back.
    const opened = secretboxOpenEasy(expectedCt, n, k);
    if (opened === null || !bytesEqual(opened, pt)) {
      failed.push(`${v.name} decrypt: got ${opened === null ? 'null' : u8ToHex(opened)}, expected ${v.plaintextHex}`);
    }
  }

  for (const m of fx.mutated) {
    total += 1;
    const ct = hexToU8(m.ciphertextHex);
    const n = hexToU8(m.nonceHex);
    const k = hexToU8(m.keyHex);
    const opened = secretboxOpenEasy(ct, n, k);
    if (opened !== null) {
      failed.push(`${m.name}: expected null, got ${u8ToHex(opened)}`);
    }
  }

  return { total, passed: total - failed.length, failed };
}
