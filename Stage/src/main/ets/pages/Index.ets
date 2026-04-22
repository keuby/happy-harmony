import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import nacl from 'libstage.so';
import { runWebrtcLoopback, LoopbackResult } from '../webrtc/loopback';

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
  @State naclSummary: string = '加载中...';
  @State addCheck: string = '';
  @State naclFailures: string[] = [];
  @State webrtcSummary: string = '等待中...';
  @State webrtcEvents: string[] = [];

  aboutToAppear(): void {
    this.runNaclTests();
    this.runWebrtc();
  }

  private async runNaclTests(): Promise<void> {
    this.naclSummary = 'running...';
    this.naclFailures = [];

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
        this.naclSummary = 'no host context';
        return;
      }
      const raw = await ctx.resourceManager.getRawFileContent('secretbox.json');
      const decoder = util.TextDecoder.create('utf-8');
      fx = JSON.parse(decoder.decodeToString(raw)) as Fixtures;
    } catch (e) {
      this.naclSummary = `fixtures load failed: ${JSON.stringify(e)}`;
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

    this.naclFailures = fails;
    this.naclSummary = `nacl: ${total - fails.length}/${total} passed`;
    hilog.info(DOMAIN, 'nacl', 'result: %{public}s', this.naclSummary);
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

  build() {
    Scroll() {
      Column() {
        Text(this.naclSummary)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 40, bottom: 6 })
        Text(this.addCheck)
          .fontSize(11)
          .fontColor(Color.Gray)
          .margin({ bottom: 14 })
        ForEach(this.naclFailures, (f: string) => {
          Text(f)
            .fontSize(10)
            .fontColor(Color.Red)
            .margin({ bottom: 3 })
            .width('100%')
        }, (f: string) => f)

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
