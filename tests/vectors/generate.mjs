#!/usr/bin/env node
// Generate deterministic secretbox test vectors using the same tweetnacl
// library that happy-agent / happy-server use in production. The HarmonyOS
// NAPI binding must match this output byte-for-byte.
//
// Usage (from repo root):
//   node happy-harmony/tests/vectors/generate.mjs
//
// Output:
//   happy-harmony/tests/vectors/secretbox.json
//
// Requires tweetnacl to be reachable; by default we resolve it from the
// happy submodule's node_modules.

import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const happyNodeModules = resolve(__dirname, '../../../happy/node_modules');
const require = createRequire(happyNodeModules + '/');
const nacl = require('tweetnacl');

const toHex = (u8) => Buffer.from(u8).toString('hex');
const fromHex = (s) => new Uint8Array(Buffer.from(s, 'hex'));

// Deterministic key/nonce — NOT for production use, only for regression.
const key = fromHex('0101010101010101010101010101010101010101010101010101010101010101');
const nonce = fromHex('020202020202020202020202020202020202020202020202');

const cases = [
  { name: 'empty', plaintext: new Uint8Array(0) },
  { name: 'one_byte', plaintext: fromHex('41') }, // 'A'
  { name: 'short_ascii', plaintext: new TextEncoder().encode('hello harmony') },
  { name: 'boundary_31', plaintext: new Uint8Array(31).map((_, i) => i) },
  { name: 'boundary_32', plaintext: new Uint8Array(32).map((_, i) => i) },
  { name: 'boundary_33', plaintext: new Uint8Array(33).map((_, i) => i) },
  { name: 'kb_block', plaintext: new Uint8Array(1024).map((_, i) => i & 0xff) },
  {
    name: 'utf8_mixed',
    plaintext: new TextEncoder().encode('Claude 会话 🚀 end-to-end'),
  },
  {
    // A concrete happy-wire-shaped payload (arbitrary JSON).
    name: 'json_session',
    plaintext: new TextEncoder().encode(
      JSON.stringify({ sid: 'abc123', role: 'user', turn: 7 }),
    ),
  },
];

const vectors = cases.map(({ name, plaintext }) => {
  const ciphertext = nacl.secretbox(plaintext, nonce, key);
  // Sanity check: round-trip here so the generator itself is verified.
  const decrypted = nacl.secretbox.open(ciphertext, nonce, key);
  if (!decrypted || toHex(decrypted) !== toHex(plaintext)) {
    throw new Error(`round-trip failed for ${name}`);
  }
  return {
    name,
    plaintextHex: toHex(plaintext),
    nonceHex: toHex(nonce),
    keyHex: toHex(key),
    ciphertextHex: toHex(ciphertext),
    plaintextLen: plaintext.length,
    ciphertextLen: ciphertext.length, // must be plaintext.length + 16 (MAC)
  };
});

// Negative cases: mutated ciphertext must fail to open.
const mutated = [];
for (const v of vectors.slice(0, 3)) {
  const ct = fromHex(v.ciphertextHex);
  if (ct.length === 0) continue;
  // Flip one bit in the MAC (first byte).
  const bad = new Uint8Array(ct);
  bad[0] ^= 0x01;
  const opened = nacl.secretbox.open(bad, nonce, key);
  if (opened !== null) throw new Error(`expected mutation of ${v.name} to fail`);
  mutated.push({ name: `${v.name}__mac_flipped`, ciphertextHex: toHex(bad), nonceHex: v.nonceHex, keyHex: v.keyHex });
}

const out = {
  generator: 'tweetnacl@' + JSON.parse(
    readFileSync(resolve(happyNodeModules, 'tweetnacl/package.json'), 'utf8'),
  ).version,
  generatedAt: new Date().toISOString(),
  note: 'XSalsa20-Poly1305 secretbox vectors. ciphertext = [16-byte MAC || encrypted payload] (the "easy" API layout).',
  vectors,
  mutated,
};

const outPath = resolve(__dirname, 'secretbox.json');
writeFileSync(outPath, JSON.stringify(out, null, 2) + '\n');
console.log(`wrote ${vectors.length} vectors + ${mutated.length} mutated cases → ${outPath}`);
