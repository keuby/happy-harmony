import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import nacl from 'libstage.so';
import { runWebrtcLoopback, LoopbackResult } from '../webrtc/loopback';

const DOMAIN = 0x0000;

interface SecretboxVector {
  name: string;
  plaintextHex: string;
  nonceHex: string;
  keyHex: string;
  ciphertextHex: string;
}

interface SecretboxMutated {
  name: string;
  ciphertextHex: string;
  nonceHex: string;
  keyHex: string;
}

interface SecretboxFixtures {
  vectors: SecretboxVector[];
  mutated: SecretboxMutated[];
}

interface BoxKeypair {
  name: string;
  seedHex: string;
  publicKeyHex: string;
  secretKeyHex: string;
}

interface BoxVector {
  name: string;
  plaintextHex: string;
  nonceHex: string;
  senderPublicKeyHex: string;
  senderSecretKeyHex: string;
  recipientPublicKeyHex: string;
  recipientSecretKeyHex: string;
  ciphertextHex: string;
}

interface BoxMutated {
  name: string;
  ciphertextHex: string;
  nonceHex: string;
  senderPublicKeyHex: string;
  recipientSecretKeyHex: string;
}

interface BoxFixtures {
  keypairs: BoxKeypair[];
  vectors: BoxVector[];
  mutated: BoxMutated[];
}

interface SignKeypairMeta {
  seedHex: string;
  publicKeyHex: string;
  secretKeyHex: string;
}

interface SignVector {
  name: string;
  messageHex: string;
  signatureHex: string;
}

interface SignMutated {
  name: string;
  messageHex: string;
  signatureHex: string;
  publicKeyHex?: string;
}

interface SignFixtures {
  keypair: SignKeypairMeta;
  vectors: SignVector[];
  mutated: SignMutated[];
}

function hexToU8(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.substr(i * 2, 2), 16);
  }
  return out;
}

function u8ToHex(u8: Uint8Array): string {
  let s = '';
  for (let i = 0; i < u8.length; i++) s += u8[i].toString(16).padStart(2, '0');
  return s;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

async function loadRawJson<T>(uiContext: UIContext, filename: string): Promise<T> {
  const ctx = uiContext.getHostContext();
  if (!ctx) throw new Error('no host context');
  const raw = await ctx.resourceManager.getRawFileContent(filename);
  const decoder = util.TextDecoder.create('utf-8');
  return JSON.parse(decoder.decodeToString(raw)) as T;
}

@Entry
@Component
struct Index {
  @State secretboxSummary: string = '加载中...';
  @State secretboxFailures: string[] = [];
  @State boxSummary: string = '等待中...';
  @State boxFailures: string[] = [];
  @State signSummary: string = '等待中...';
  @State signFailures: string[] = [];
  @State webrtcSummary: string = '等待中...';
  @State webrtcEvents: string[] = [];

  aboutToAppear(): void {
    this.runSecretboxTests();
    this.runBoxTests();
    this.runSignTests();
    this.runWebrtc();
  }

  private async runSecretboxTests(): Promise<void> {
    this.secretboxSummary = 'secretbox: running...';
    this.secretboxFailures = [];

    let fx: SecretboxFixtures;
    try {
      fx = await loadRawJson<SecretboxFixtures>(this.getUIContext(), 'secretbox.json');
    } catch (e) {
      this.secretboxSummary = `secretbox fixtures load failed: ${JSON.stringify(e)}`;
      return;
    }

    const fails: string[] = [];
    let total = 0;

    for (const v of fx.vectors) {
      total += 2;
      const pt = hexToU8(v.plaintextHex);
      const n = hexToU8(v.nonceHex);
      const k = hexToU8(v.keyHex);
      const expected = hexToU8(v.ciphertextHex);

      try {
        const ct = nacl.secretboxEasy(pt, n, k);
        if (!bytesEqual(ct, expected)) {
          fails.push(`${v.name} enc mismatch: got ${u8ToHex(ct)}`);
        }
      } catch (e) {
        fails.push(`${v.name} enc threw: ${JSON.stringify(e)}`);
      }

      try {
        const opened = nacl.secretboxOpenEasy(expected, n, k);
        if (opened === null || !bytesEqual(opened, pt)) {
          fails.push(`${v.name} dec mismatch: got ${opened === null ? 'null' : u8ToHex(opened)}`);
        }
      } catch (e) {
        fails.push(`${v.name} dec threw: ${JSON.stringify(e)}`);
      }
    }

    for (const m of fx.mutated) {
      total += 1;
      try {
        const opened = nacl.secretboxOpenEasy(hexToU8(m.ciphertextHex), hexToU8(m.nonceHex), hexToU8(m.keyHex));
        if (opened !== null) {
          fails.push(`${m.name} should be null, got ${u8ToHex(opened)}`);
        }
      } catch (e) {
        fails.push(`${m.name} threw: ${JSON.stringify(e)}`);
      }
    }

    this.secretboxFailures = fails;
    this.secretboxSummary = `secretbox: ${total - fails.length}/${total} passed`;
    hilog.info(DOMAIN, 'nacl', 'secretbox: %{public}s', this.secretboxSummary);
  }

  private async runBoxTests(): Promise<void> {
    this.boxSummary = 'box: running...';
    this.boxFailures = [];

    let fx: BoxFixtures;
    try {
      fx = await loadRawJson<BoxFixtures>(this.getUIContext(), 'box.json');
    } catch (e) {
      this.boxSummary = `box fixtures load failed: ${JSON.stringify(e)}`;
      return;
    }

    const fails: string[] = [];
    let total = 0;

    // Keypair derivation: seed → publicKey/secretKey must match fixture.
    for (const kp of fx.keypairs) {
      total += 1;
      try {
        const derived = nacl.cryptoBoxKeypairFromSeed(hexToU8(kp.seedHex));
        const expectedPk = hexToU8(kp.publicKeyHex);
        const expectedSk = hexToU8(kp.secretKeyHex);
        if (!bytesEqual(derived.publicKey, expectedPk) || !bytesEqual(derived.secretKey, expectedSk)) {
          fails.push(`${kp.name} keypair mismatch: pk=${u8ToHex(derived.publicKey)} sk=${u8ToHex(derived.secretKey)}`);
        }
      } catch (e) {
        fails.push(`${kp.name} keypair threw: ${JSON.stringify(e)}`);
      }
    }

    // Random keypair sanity: pk must equal scalarmult_base(sk), i.e. the
    // seed form must round-trip to the same public key.
    total += 1;
    try {
      const random = nacl.cryptoBoxKeypair();
      const rederived = nacl.cryptoBoxKeypairFromSeed(random.secretKey);
      if (!bytesEqual(rederived.publicKey, random.publicKey)) {
        fails.push(`random keypair pk != scalarmult_base(sk)`);
      }
    } catch (e) {
      fails.push(`random keypair threw: ${JSON.stringify(e)}`);
    }

    for (const v of fx.vectors) {
      total += 2;
      const pt = hexToU8(v.plaintextHex);
      const n = hexToU8(v.nonceHex);
      const recipPk = hexToU8(v.recipientPublicKeyHex);
      const senderSk = hexToU8(v.senderSecretKeyHex);
      const senderPk = hexToU8(v.senderPublicKeyHex);
      const recipSk = hexToU8(v.recipientSecretKeyHex);
      const expected = hexToU8(v.ciphertextHex);

      try {
        const ct = nacl.cryptoBoxEasy(pt, n, recipPk, senderSk);
        if (!bytesEqual(ct, expected)) {
          fails.push(`${v.name} enc mismatch: got ${u8ToHex(ct)}`);
        }
      } catch (e) {
        fails.push(`${v.name} enc threw: ${JSON.stringify(e)}`);
      }

      try {
        const opened = nacl.cryptoBoxOpenEasy(expected, n, senderPk, recipSk);
        if (opened === null || !bytesEqual(opened, pt)) {
          fails.push(`${v.name} dec mismatch: got ${opened === null ? 'null' : u8ToHex(opened)}`);
        }
      } catch (e) {
        fails.push(`${v.name} dec threw: ${JSON.stringify(e)}`);
      }
    }

    for (const m of fx.mutated) {
      total += 1;
      try {
        const opened = nacl.cryptoBoxOpenEasy(
          hexToU8(m.ciphertextHex),
          hexToU8(m.nonceHex),
          hexToU8(m.senderPublicKeyHex),
          hexToU8(m.recipientSecretKeyHex),
        );
        if (opened !== null) {
          fails.push(`${m.name} should be null, got ${u8ToHex(opened)}`);
        }
      } catch (e) {
        fails.push(`${m.name} threw: ${JSON.stringify(e)}`);
      }
    }

    this.boxFailures = fails;
    this.boxSummary = `box: ${total - fails.length}/${total} passed`;
    hilog.info(DOMAIN, 'nacl', 'box: %{public}s', this.boxSummary);
  }

  private async runSignTests(): Promise<void> {
    this.signSummary = 'sign: running...';
    this.signFailures = [];

    let fx: SignFixtures;
    try {
      fx = await loadRawJson<SignFixtures>(this.getUIContext(), 'sign.json');
    } catch (e) {
      this.signSummary = `sign fixtures load failed: ${JSON.stringify(e)}`;
      return;
    }

    const fails: string[] = [];
    let total = 0;

    const seed = hexToU8(fx.keypair.seedHex);
    const expectedPk = hexToU8(fx.keypair.publicKeyHex);
    const expectedSk = hexToU8(fx.keypair.secretKeyHex);

    total += 1;
    let derivedSk: Uint8Array | null = null;
    try {
      const derived = nacl.cryptoSignKeypairFromSeed(seed);
      derivedSk = derived.secretKey;
      if (!bytesEqual(derived.publicKey, expectedPk) || !bytesEqual(derived.secretKey, expectedSk)) {
        fails.push(`sign keypair mismatch: pk=${u8ToHex(derived.publicKey)}`);
      }
    } catch (e) {
      fails.push(`sign keypair threw: ${JSON.stringify(e)}`);
    }

    const sk = derivedSk !== null ? derivedSk : expectedSk;

    for (const v of fx.vectors) {
      total += 2;
      const msg = hexToU8(v.messageHex);
      const expectedSig = hexToU8(v.signatureHex);

      try {
        const sig = nacl.cryptoSignDetached(msg, sk);
        if (!bytesEqual(sig, expectedSig)) {
          fails.push(`${v.name} sign mismatch: got ${u8ToHex(sig)}`);
        }
      } catch (e) {
        fails.push(`${v.name} sign threw: ${JSON.stringify(e)}`);
      }

      try {
        const ok = nacl.cryptoSignVerifyDetached(expectedSig, msg, expectedPk);
        if (!ok) {
          fails.push(`${v.name} verify failed for valid signature`);
        }
      } catch (e) {
        fails.push(`${v.name} verify threw: ${JSON.stringify(e)}`);
      }
    }

    for (const m of fx.mutated) {
      total += 1;
      try {
        const pk = m.publicKeyHex ? hexToU8(m.publicKeyHex) : expectedPk;
        const ok = nacl.cryptoSignVerifyDetached(
          hexToU8(m.signatureHex),
          hexToU8(m.messageHex),
          pk,
        );
        if (ok) {
          fails.push(`${m.name} should be invalid, verify returned true`);
        }
      } catch (e) {
        fails.push(`${m.name} threw: ${JSON.stringify(e)}`);
      }
    }

    this.signFailures = fails;
    this.signSummary = `sign: ${total - fails.length}/${total} passed`;
    hilog.info(DOMAIN, 'nacl', 'sign: %{public}s', this.signSummary);
  }

  private async runWebrtc(): Promise<void> {
    this.webrtcSummary = 'webrtc: running...';
    try {
      const result: LoopbackResult = await runWebrtcLoopback();
      this.webrtcEvents = result.events;
      this.webrtcSummary = `webrtc: ${result.summary}`;
      hilog.info(DOMAIN, 'webrtc', 'result: %{public}s', this.webrtcSummary);
    } catch (e) {
      this.webrtcSummary = `webrtc threw: ${JSON.stringify(e)}`;
      hilog.error(DOMAIN, 'webrtc', 'threw: %{public}s', JSON.stringify(e));
    }
  }

  @Builder
  private FailureList(items: string[]) {
    ForEach(items, (f: string) => {
      Text(f)
        .fontSize(10)
        .fontColor(Color.Red)
        .margin({ bottom: 3 })
        .width('100%')
    }, (f: string) => f)
  }

  build() {
    Scroll() {
      Column() {
        Text(this.secretboxSummary)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 40, bottom: 10 })
        this.FailureList(this.secretboxFailures)

        Divider().margin({ top: 16, bottom: 16 })

        Text(this.boxSummary)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 10 })
        this.FailureList(this.boxFailures)

        Divider().margin({ top: 16, bottom: 16 })

        Text(this.signSummary)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 10 })
        this.FailureList(this.signFailures)

        Divider().margin({ top: 16, bottom: 16 })

        Text(this.webrtcSummary)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 10 })
        ForEach(this.webrtcEvents, (e: string, i: number) => {
          Text(`${i + 1}. ${e}`)
            .fontSize(10)
            .fontColor(Color.Gray)
            .margin({ bottom: 2 })
            .width('100%')
        }, (e: string, i: number) => `${i}-${e}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 40 })
    }
    .width('100%')
    .height('100%')
  }
}
