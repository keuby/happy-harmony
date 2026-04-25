#!/usr/bin/env node
// Generate deterministic nacl test vectors using the same tweetnacl
// library that happy-agent / happy-server use in production. The HarmonyOS
// NAPI bindings must match this output byte-for-byte.
//
// Usage (from repo root):
//   node happy-harmony/tests/vectors/generate.mjs
//
// Outputs:
//   happy-harmony/tests/vectors/secretbox.json  — XSalsa20-Poly1305
//   happy-harmony/tests/vectors/box.json        — X25519 + XSalsa20-Poly1305
//   happy-harmony/tests/vectors/sign.json       — Ed25519 detached signatures
//
// Requires tweetnacl to be reachable; by default we resolve it from the
// happy submodule's node_modules.

import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { createHash } from 'node:crypto';

const __dirname = dirname(fileURLToPath(import.meta.url));
const happyNodeModules = resolve(__dirname, '../../../happy/node_modules');
const require = createRequire(happyNodeModules + '/');
const nacl = require('tweetnacl');

// libsodium's crypto_box_seed_keypair: sk = SHA-512(seed)[0..32];
// pk = scalarmult_base(sk). tweetnacl-js's box.keyPair.fromSecretKey
// uses the seed directly as sk (no hash) — that's a different keypair.
// happy-app + happy-server use sodium.crypto_box_seed_keypair, so the
// HarmonyOS NAPI must match the libsodium derivation, not tweetnacl's.
function libsodiumBoxSeedKeypair(seed) {
  const sk = new Uint8Array(createHash('sha512').update(Buffer.from(seed)).digest().slice(0, 32));
  return nacl.box.keyPair.fromSecretKey(sk);
}

const toHex = (u8) => Buffer.from(u8).toString('hex');
const fromHex = (s) => new Uint8Array(Buffer.from(s, 'hex'));

const tweetnaclVersion = JSON.parse(
  readFileSync(resolve(happyNodeModules, 'tweetnacl/package.json'), 'utf8'),
).version;
const generatedAt = new Date().toISOString();

// ---------------------------------------------------------------------------
// secretbox (XSalsa20-Poly1305)
// ---------------------------------------------------------------------------

{
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
      name: 'json_session',
      plaintext: new TextEncoder().encode(
        JSON.stringify({ sid: 'abc123', role: 'user', turn: 7 }),
      ),
    },
  ];

  const vectors = cases.map(({ name, plaintext }) => {
    const ciphertext = nacl.secretbox(plaintext, nonce, key);
    const decrypted = nacl.secretbox.open(ciphertext, nonce, key);
    if (!decrypted || toHex(decrypted) !== toHex(plaintext)) {
      throw new Error(`secretbox round-trip failed for ${name}`);
    }
    return {
      name,
      plaintextHex: toHex(plaintext),
      nonceHex: toHex(nonce),
      keyHex: toHex(key),
      ciphertextHex: toHex(ciphertext),
      plaintextLen: plaintext.length,
      ciphertextLen: ciphertext.length,
    };
  });

  const mutated = [];
  for (const v of vectors.slice(0, 3)) {
    const ct = fromHex(v.ciphertextHex);
    if (ct.length === 0) continue;
    const bad = new Uint8Array(ct);
    bad[0] ^= 0x01;
    const opened = nacl.secretbox.open(bad, nonce, key);
    if (opened !== null) throw new Error(`expected secretbox mutation of ${v.name} to fail`);
    mutated.push({
      name: `${v.name}__mac_flipped`,
      ciphertextHex: toHex(bad),
      nonceHex: v.nonceHex,
      keyHex: v.keyHex,
    });
  }

  const out = {
    generator: 'tweetnacl@' + tweetnaclVersion,
    generatedAt,
    note: 'XSalsa20-Poly1305 secretbox. ciphertext = [16-byte MAC || encrypted payload].',
    vectors,
    mutated,
  };
  const outPath = resolve(__dirname, 'secretbox.json');
  writeFileSync(outPath, JSON.stringify(out, null, 2) + '\n');
  console.log(`secretbox: ${vectors.length} + ${mutated.length} mutated → ${outPath}`);
}

// ---------------------------------------------------------------------------
// box (X25519 + XSalsa20-Poly1305, authenticated)
// ---------------------------------------------------------------------------

{
  // Deterministic seeds for both ends. libsodiumBoxSeedKeypair(seed)
  // maps seed → SHA-512(seed)[0..32] = sk → scalarmult_base(sk) = pk
  // — matches libsodium's crypto_box_seed_keypair, which is what
  // happy-app uses upstream and what the harmony NAPI now does.
  const senderSeed = fromHex('aa'.repeat(32));
  const recipSeed = fromHex('bb'.repeat(32));
  const sender = libsodiumBoxSeedKeypair(senderSeed);
  const recipient = libsodiumBoxSeedKeypair(recipSeed);
  const nonce = fromHex('030303030303030303030303030303030303030303030303');

  const keypairs = [
    { name: 'sender', seedHex: toHex(senderSeed), publicKeyHex: toHex(sender.publicKey), secretKeyHex: toHex(sender.secretKey) },
    { name: 'recipient', seedHex: toHex(recipSeed), publicKeyHex: toHex(recipient.publicKey), secretKeyHex: toHex(recipient.secretKey) },
  ];

  const cases = [
    { name: 'empty', plaintext: new Uint8Array(0) },
    { name: 'one_byte', plaintext: fromHex('42') },
    { name: 'short_ascii', plaintext: new TextEncoder().encode('hello box') },
    { name: 'boundary_31', plaintext: new Uint8Array(31).map((_, i) => i) },
    { name: 'boundary_32', plaintext: new Uint8Array(32).map((_, i) => i) },
    { name: 'boundary_33', plaintext: new Uint8Array(33).map((_, i) => i) },
    { name: 'kb_block', plaintext: new Uint8Array(1024).map((_, i) => i & 0xff) },
  ];

  const vectors = cases.map(({ name, plaintext }) => {
    const ciphertext = nacl.box(plaintext, nonce, recipient.publicKey, sender.secretKey);
    const opened = nacl.box.open(ciphertext, nonce, sender.publicKey, recipient.secretKey);
    if (!opened || toHex(opened) !== toHex(plaintext)) {
      throw new Error(`box round-trip failed for ${name}`);
    }
    return {
      name,
      plaintextHex: toHex(plaintext),
      nonceHex: toHex(nonce),
      senderPublicKeyHex: toHex(sender.publicKey),
      senderSecretKeyHex: toHex(sender.secretKey),
      recipientPublicKeyHex: toHex(recipient.publicKey),
      recipientSecretKeyHex: toHex(recipient.secretKey),
      ciphertextHex: toHex(ciphertext),
      plaintextLen: plaintext.length,
      ciphertextLen: ciphertext.length,
    };
  });

  const mutated = [];
  for (const v of vectors.slice(0, 3)) {
    const ct = fromHex(v.ciphertextHex);
    if (ct.length === 0) continue;
    const bad = new Uint8Array(ct);
    bad[0] ^= 0x01;
    const opened = nacl.box.open(bad, nonce, sender.publicKey, recipient.secretKey);
    if (opened !== null) throw new Error(`expected box mutation of ${v.name} to fail`);
    mutated.push({
      name: `${v.name}__mac_flipped`,
      ciphertextHex: toHex(bad),
      nonceHex: v.nonceHex,
      senderPublicKeyHex: v.senderPublicKeyHex,
      recipientSecretKeyHex: v.recipientSecretKeyHex,
    });
  }

  const out = {
    generator: 'tweetnacl@' + tweetnaclVersion,
    generatedAt,
    note: 'X25519 + XSalsa20-Poly1305 authenticated box. ciphertext = [16-byte MAC || encrypted payload]. Keypairs derived via libsodium-style crypto_box_seed_keypair (sk = SHA-512(seed)[0..32]).',
    keypairs,
    vectors,
    mutated,
  };
  const outPath = resolve(__dirname, 'box.json');
  writeFileSync(outPath, JSON.stringify(out, null, 2) + '\n');
  console.log(`box: ${vectors.length} + ${mutated.length} mutated → ${outPath}`);
}

// ---------------------------------------------------------------------------
// sign (Ed25519 detached signatures)
// ---------------------------------------------------------------------------

{
  const seed = fromHex('cc'.repeat(32));
  const signer = nacl.sign.keyPair.fromSeed(seed);

  const cases = [
    { name: 'empty', message: new Uint8Array(0) },
    { name: 'one_byte', message: fromHex('43') },
    { name: 'short_ascii', message: new TextEncoder().encode('hello sign') },
    { name: 'challenge_32', message: new Uint8Array(32).map((_, i) => (i * 7) & 0xff) },
    { name: 'kb_block', message: new Uint8Array(1024).map((_, i) => i & 0xff) },
    {
      name: 'auth_challenge_shape',
      message: new TextEncoder().encode(
        JSON.stringify({ challenge: 'abc123', timestamp: 1700000000 }),
      ),
    },
  ];

  const vectors = cases.map(({ name, message }) => {
    const signature = nacl.sign.detached(message, signer.secretKey);
    if (!nacl.sign.detached.verify(message, signature, signer.publicKey)) {
      throw new Error(`sign verify failed for ${name}`);
    }
    return {
      name,
      messageHex: toHex(message),
      signatureHex: toHex(signature),
      messageLen: message.length,
    };
  });

  // Negative cases: verify must reject mutated sig, wrong pk, and mutated message.
  const mutated = [];
  const fixedVec = vectors[2]; // short_ascii
  {
    const sig = fromHex(fixedVec.signatureHex);
    const bad = new Uint8Array(sig);
    bad[0] ^= 0x01;
    if (nacl.sign.detached.verify(fromHex(fixedVec.messageHex), bad, signer.publicKey)) {
      throw new Error('expected mutated-sig verify to fail');
    }
    mutated.push({
      name: 'short_ascii__sig_flipped',
      messageHex: fixedVec.messageHex,
      signatureHex: toHex(bad),
      expect: 'invalid',
    });
  }
  {
    // Wrong public key — use the recipient's key from box section (different).
    const otherSeed = fromHex('dd'.repeat(32));
    const other = nacl.sign.keyPair.fromSeed(otherSeed);
    if (nacl.sign.detached.verify(fromHex(fixedVec.messageHex), fromHex(fixedVec.signatureHex), other.publicKey)) {
      throw new Error('expected wrong-pk verify to fail');
    }
    mutated.push({
      name: 'short_ascii__wrong_pk',
      messageHex: fixedVec.messageHex,
      signatureHex: fixedVec.signatureHex,
      publicKeyHex: toHex(other.publicKey),
      expect: 'invalid',
    });
  }
  {
    const msg = fromHex(fixedVec.messageHex);
    const bad = new Uint8Array(msg);
    bad[0] ^= 0x01;
    if (nacl.sign.detached.verify(bad, fromHex(fixedVec.signatureHex), signer.publicKey)) {
      throw new Error('expected mutated-msg verify to fail');
    }
    mutated.push({
      name: 'short_ascii__msg_flipped',
      messageHex: toHex(bad),
      signatureHex: fixedVec.signatureHex,
      expect: 'invalid',
    });
  }

  const out = {
    generator: 'tweetnacl@' + tweetnaclVersion,
    generatedAt,
    note: 'Ed25519 detached signatures. Keypair derived via sign.keyPair.fromSeed(seed).',
    keypair: {
      seedHex: toHex(seed),
      publicKeyHex: toHex(signer.publicKey),
      secretKeyHex: toHex(signer.secretKey),
    },
    vectors,
    mutated,
  };
  const outPath = resolve(__dirname, 'sign.json');
  writeFileSync(outPath, JSON.stringify(out, null, 2) + '\n');
  console.log(`sign: ${vectors.length} + ${mutated.length} mutated → ${outPath}`);
}
