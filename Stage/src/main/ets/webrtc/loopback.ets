// PoC-A1: WebRTC loopback between two local RTCPeerConnection instances.
// No network, no STUN/TURN, no media — just signaling + DataChannel roundtrip
// to confirm the @ohos/webrtc prebuilt libohos_webrtc.so loads and runs.

import webrtc from '@ohos/webrtc';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface LoopbackResult {
  ok: boolean;
  summary: string;
  events: string[];
}

export async function runWebrtcLoopback(): Promise<LoopbackResult> {
  const events: string[] = [];
  const push = (msg: string): void => {
    events.push(msg);
    hilog.info(0x0000, 'webrtc', 'step: %{public}s', msg);
  };
  const started = Date.now();

  let peerA: webrtc.RTCPeerConnection | null = null;
  let peerB: webrtc.RTCPeerConnection | null = null;

  try {
    push('new PeerConnectionFactory()');
    const factory = new webrtc.PeerConnectionFactory();

    push('factory.createPeerConnection(×2)');
    peerA = factory.createPeerConnection({ iceServers: [] });
    peerB = factory.createPeerConnection({ iceServers: [] });

    // Trickle ICE candidates between the two local peers.
    peerA.onicecandidate = (ev: webrtc.RTCPeerConnectionIceEvent): void => {
      if (ev.candidate && peerB) {
        peerB.addIceCandidate({
          candidate: ev.candidate.candidate,
          sdpMid: ev.candidate.sdpMid,
          sdpMLineIndex: ev.candidate.sdpMLineIndex,
        }).catch((e: Error) => push(`peerB.addIceCandidate threw: ${e.message ?? e}`));
      }
    };
    peerB.onicecandidate = (ev: webrtc.RTCPeerConnectionIceEvent): void => {
      if (ev.candidate && peerA) {
        peerA.addIceCandidate({
          candidate: ev.candidate.candidate,
          sdpMid: ev.candidate.sdpMid,
          sdpMLineIndex: ev.candidate.sdpMLineIndex,
        }).catch((e: Error) => push(`peerA.addIceCandidate threw: ${e.message ?? e}`));
      }
    };

    peerA.onconnectionstatechange = (): void => push(`peerA: ${peerA!.connectionState}`);
    peerB.onconnectionstatechange = (): void => push(`peerB: ${peerB!.connectionState}`);

    // Roundtrip: peerA opens a channel, sends "hello from A"; peerB echoes
    // "ack: hello from A"; peerA waits for that echo. 10s timeout.
    const echoPromise = new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('timeout waiting for echo (10s)')), 10000);

      peerB!.ondatachannel = (ev: webrtc.RTCDataChannelEvent): void => {
        const dc = ev.channel;
        push(`peerB ondatachannel (label=${dc.label})`);
        dc.onmessage = (msg: webrtc.MessageEvent): void => {
          const text = typeof msg.data === 'string' ? msg.data : '(non-string)';
          push(`peerB received: "${text}"`);
          dc.send(`ack: ${text}`);
        };
      };

      const dcA = peerA!.createDataChannel('poc');
      dcA.onopen = (): void => {
        push('peerA datachannel open, sending "hello from A"');
        dcA.send('hello from A');
      };
      dcA.onmessage = (msg: webrtc.MessageEvent): void => {
        clearTimeout(timer);
        resolve(typeof msg.data === 'string' ? msg.data : '(non-string)');
      };
      dcA.onerror = (ev: webrtc.Event): void => {
        clearTimeout(timer);
        reject(new Error(`dcA.onerror: ${JSON.stringify(ev)}`));
      };
    });

    push('signaling: createOffer');
    const offer = await peerA.createOffer();
    await peerA.setLocalDescription(offer);
    await peerB.setRemoteDescription(offer);
    push('signaling: createAnswer');
    const answer = await peerB.createAnswer();
    await peerB.setLocalDescription(answer);
    await peerA.setRemoteDescription(answer);
    push('handshake done, awaiting echo...');

    const ack = await echoPromise;
    const elapsed = Date.now() - started;

    peerA.close();
    peerB.close();

    if (ack === 'ack: hello from A') {
      push(`✓ echo roundtrip OK (${elapsed}ms)`);
      return { ok: true, summary: `loopback OK (${elapsed}ms)`, events };
    }
    return { ok: false, summary: `wrong echo: "${ack}"`, events };
  } catch (e) {
    const err = e as Error;
    if (peerA) try { peerA.close(); } catch { /* ignore */ }
    if (peerB) try { peerB.close(); } catch { /* ignore */ }
    return { ok: false, summary: `threw: ${err.message ?? err}`, events };
  }
}
