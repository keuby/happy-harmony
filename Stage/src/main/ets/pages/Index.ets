import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import nacl from 'libstage.so';

const DOMAIN = 0x0000;

interface Vector {
  name: string;
  plaintextHex: string;
  nonceHex: string;
  keyHex: string;
  ciphertextHex: string;
}

interface Mutated {
  name: string;
  ciphertextHex: string;
  nonceHex: string;
  keyHex: string;
}

interface Fixtures {
  vectors: Vector[];
  mutated: Mutated[];
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

@Entry
@Component
struct Index {
  @State summary: string = '加载中...';
  @State addCheck: string = '';
  @State failures: string[] = [];

  aboutToAppear(): void {
    this.runTests();
  }

  private async runTests(): Promise<void> {
    this.summary = 'running...';
    this.failures = [];

    try {
      const sum = nacl.add(2, 3);
      this.addCheck = `sanity: add(2,3) = ${sum}`;
    } catch (e) {
      this.addCheck = `add() threw: ${JSON.stringify(e)}`;
    }

    let fx: Fixtures;
    try {
      const ctx = this.getUIContext().getHostContext();
      if (!ctx) {
        this.summary = 'no host context';
        return;
      }
      const raw = await ctx.resourceManager.getRawFileContent('secretbox.json');
      const decoder = util.TextDecoder.create('utf-8');
      fx = JSON.parse(decoder.decodeToString(raw)) as Fixtures;
    } catch (e) {
      this.summary = `fixtures load failed: ${JSON.stringify(e)}`;
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

    this.failures = fails;
    this.summary = `${total - fails.length}/${total} passed`;
    hilog.info(DOMAIN, 'nacl', 'result: %{public}s', this.summary);
  }

  build() {
    Column() {
      Text(this.summary)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 40, bottom: 12 })

      Text(this.addCheck)
        .fontSize(12)
        .fontColor(Color.Gray)
        .margin({ bottom: 20 })

      Button('Run secretbox vectors')
        .onClick(() => { this.runTests(); })
        .margin({ bottom: 20 })

      Scroll() {
        Column() {
          ForEach(this.failures, (f: string) => {
            Text(f)
              .fontSize(11)
              .fontColor(Color.Red)
              .margin({ bottom: 6 })
              .width('100%')
          }, (f: string) => f)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .padding({ left: 16, right: 16 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }
}
