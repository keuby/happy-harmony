# happy-harmony 进度

HarmonyOS Next 原生 ArkTS 版 slopus/happy。本文件是跨阶段进度的**单一可信来源**——每完成里程碑更新这里，不新建状态文档。

> 最后更新：2026-04-23

## Phase 0 — 关键风险验证 ✅ 完结

目标：把"纯 ArkTS 原生方案"的两个最高风险（E2E 加密、WebRTC）实际跑通，否则方案要重谈。

| PoC | 目标 | 状态 | 产物 |
|---|---|---|---|
| **PoC-A2** libsodium NAPI | TweetNaCl 编进 .so，secretbox 在真机上和 tweetnacl-js 字节级一致 | ✅ **21/21 passed** on HarmonyOS Next 6.0.2 (API 22) | [01-libsodium-feasibility.md](./01-libsodium-feasibility.md) · commit `d215ee6` |
| **PoC-A1** WebRTC | 两个 RTCPeerConnection 在真机上 offer/answer + DataChannel 回环 | ✅ **loopback OK (77 ms)** | [00-livekit-webrtc-feasibility.md](./00-livekit-webrtc-feasibility.md)（部分过时，见下） · commit `5fc5997` |

### 关键事实（覆盖 00-livekit-webrtc-feasibility.md 过时结论）

原调研估 WebRTC 方案 A 要 **8-14 人月**，基于"自港 libwebrtc + NAPI + Camera/Audio/Codec 适配"。真机验证发现：

- Archermind 维护的 **`@ohos/webrtc`** ohpm 包直接可用（Apache-2.0）
- 11 MB 预编译 aarch64 `libohos_webrtc.so` + 1046 行 W3C 风格 TS 声明
- `compatibleSdkVersion: 12`（设备 22 兼容），**零 NDK 编译，零 depot_tools，零 third_party 下载**
- 从零到 loopback 跑通 < 1 小时

**工作量修正**：WebRTC 侧从 8-14 人月 → **1-2 人月**，瓶颈转为 LiveKit 信令协议（WebSocket + protobuf v9）层。

### 方案 B（换 RTC 厂商）彻底出局的依据

happy 的 LiveKit 实际是 ElevenLabs ConvAI 的底层传输（见 `happy-server/sources/app/api/routes/voiceRoutes.ts:154-170`）。换 RTC 厂商等于放弃 ElevenLabs 语音 agent 栈，工作量 20+ 人月。

## Phase 1 — 项目骨架 + 核心模块

| 轨道 | 内容 | 状态 |
|---|---|---|
| **1c** nacl 补全 | `crypto_box_*` + `crypto_sign_*` NAPI 扩展（authQR 登录必需） | ✅ 真机全绿（见下） |
| **1a** 项目脚手架 | navigation、状态管理、网络层（rcp）、本地存储、主题 | ⏸ 未开始 |
| **1b** LiveKit 客户端 | WebSocket + protobuf v9 信令层 → `@ohos/webrtc` | ⏸ 依赖 1a |
| **1d** `happy-wire` 协议 | Zod → ArkTS 类型移植 | ⏸ 依赖 1a |

推荐顺序：**1a 和 1c 可并行**（骨架 vs 小而确定的补强，互不阻塞）。1b 和 1d 依赖 1a。1c 已落地，接下来进 1a。

### Phase 1c — nacl NAPI 补全 ✅ 完结

扩展 PoC-A2 的 `libnacl.so` / `libstage.so`，覆盖 happy authQR 登录 + `encryptBox` 用到的 libsodium 子集。真机（HarmonyOS Next 6.0.2 / API 22）跑 tweetnacl-js 1.0.3 对拍 fixture，**secretbox 21/21、box 20/20、sign 16/16 全绿**。

- **tweetnacl patch**：加 `crypto_sign_keypair_from_seed`（`scalarbase`/`pack` 是 static，helper 必须同文件，标 `LOCAL PATCH`）
- **NAPI 绑定**：`cryptoBoxKeypair` / `cryptoBoxKeypairFromSeed` / `cryptoBoxEasy` / `cryptoBoxOpenEasy` / `cryptoSignKeypairFromSeed` / `cryptoSignDetached` / `cryptoSignVerifyDetached`（`packages/nacl` + `Stage/` 双份手动同步，1a 再整）
- **对拍 fixture**：`tests/vectors/{box,sign}.json` 由 `generate.mjs` 产出；真机 rawfile 里同名 JSON 为 Stage 读取的副本
- **Stage 测试页**：`Stage/src/main/ets/pages/Index.ets` 扩出 secretbox / box / sign 三个 section + 原有 webrtc loopback

## Phase 2+ — 未规划

UI 页面、WebRTC 音频采集/播放、推送（HMS Push）、支付等，等 Phase 1 推进后再分支。

## 仓库结构速查

- `docs/` — 调研文档 + 本进度表
- `packages/nacl/` — PoC-A2 独立 NAPI 模块源码（源头），同一份源码内嵌进 Stage/ 用于真机验证
- `Stage/` — DevEco Native C++ 应用模块（entry 就是这个模块，名字叫 Stage）
- `libs/webrtc-1.0.0.har` — vendored `@ohos/webrtc`（绕开 ohpm 镜像超时）
- `tests/vectors/` — tweetnacl-js 生成的 secretbox 对拍 fixture

## 更新纪律

- 每次 PoC/里程碑推进后，改这一个文件
- 调研/设计类新文档可以新开（编号如 `02-*.md`），但"进度状态"只走本文件
- commit message 里写技术细节；本文件写**现在到哪了、下一步做什么**，要能让翻开它的人 3 分钟对齐
