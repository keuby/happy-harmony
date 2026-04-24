# happy-harmony 进度

HarmonyOS Next 原生 ArkTS 版 slopus/happy。本文件是跨阶段进度的**单一可信来源**——每完成里程碑更新这里，不新建状态文档。

> 最后更新：2026-04-25

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
| **1c** nacl 补全 | `crypto_box_*` + `crypto_sign_*` NAPI 扩展（authQR 登录必需） | ✅ 真机全绿 |
| **1a** 项目脚手架 | MVVM 目录、Navigation、api 层、主题 token、wire HAR、会话列表骨架 | ✅ 真机端到端验证 |
| **1b** LiveKit 客户端 | WebSocket + protobuf v9 信令层 → `@ohos/webrtc` | ⏸ 依赖 1a |
| **1d** `happy-wire` 协议 | Zod → ArkTS 类型移植（authQR + session 已移，messages / realtime 待补） | ⏳ 部分（随 1b/PoC-A3 逐步扩） |
| **1e** nacl HAR 化 | `packages/nacl` 升级为真正的 HAR 模块（带 native 编译），替换 `Stage/` 里的双份同步副本 | ⏸ blocked by 1a |
| **PoC-A3** AES-256-GCM 互操作 | 对拍 `rn-encryption` 的 AES-GCM wire 布局，用 `@ohos.security.cryptoFramework` 解 session metadata/agentState | ⏸ 独立 PoC 节奏 |

1a 已完结（见下）。剩余 1b / 1d / 1e / PoC-A3 可并行推进——1e 和 PoC-A3 互不依赖，1b 单独沿 WebRTC/LiveKit 线。

### Phase 1c — nacl NAPI 补全 ✅ 完结

扩展 PoC-A2 的 `libnacl.so` / `libstage.so`，覆盖 happy authQR 登录 + `encryptBox` 用到的 libsodium 子集。真机（HarmonyOS Next 6.0.2 / API 22）跑 tweetnacl-js 1.0.3 对拍 fixture，**secretbox 21/21、box 20/20、sign 16/16 全绿**。

- **tweetnacl patch**：加 `crypto_sign_keypair_from_seed`（`scalarbase`/`pack` 是 static，helper 必须同文件，标 `LOCAL PATCH`）
- **NAPI 绑定**：`cryptoBoxKeypair` / `cryptoBoxKeypairFromSeed` / `cryptoBoxEasy` / `cryptoBoxOpenEasy` / `cryptoSignKeypairFromSeed` / `cryptoSignDetached` / `cryptoSignVerifyDetached`（`packages/nacl` + `Stage/` 双份手动同步，1a 再整）
- **对拍 fixture**：`tests/vectors/{box,sign}.json` 由 `generate.mjs` 产出；真机 rawfile 里同名 JSON 为 Stage 读取的副本
- **Stage 测试页**：`Stage/src/main/ets/pages/Index.ets` 扩出 secretbox / box / sign 三个 section + 原有 webrtc loopback

### Phase 1a — 项目脚手架 ✅ 完结

2026-04-25 真机端到端验证：harmony 客户端 → 自建 `happy.cdkchen.com` → `GET /v1/sessions` → List UI 渲染 2 条真实会话。Stage 模块与 `packages/wire` HAR 共同编译通过，零 error，仅残留 `@ohos/webrtc` 第三方 HAR 的 string resource 冲突 warning（已确认与本项目无关）。

**子任务落地**：

1. **MVVM 目录重构**：`auth/` → `service/auth/`、`encryption/` → `common/crypto/`、`sync/` → `api/`、新增 `viewmodel/ model/ components/ common/constants/`，删 `theme/`。
2. **Resources 双份主题 token**：`resources/base/element/color.json` + `resources/dark/element/color.json` 铺 10 个 token；组件全部切到 `$r('app.color.xxx')`，TS 侧 `Colors` 常量已删。
3. **Navigation 路由容器**：`Index.ets` 套 `Navigation(pageStack)`，内部暂沿用条件渲染（login / home），Phase 2 加会话详情时直接切 NavDestination。
4. **api 层拆分**：`sync/apiSocket.ets` → `api/rest.ets`（HTTP 完整：base URL、X-Happy-Client、bearer token、ApiError 包装）。`api/socket.ets` 留给 Phase 1b WebSocket 层。
5. **`packages/wire` HAR**：独立 HAR 模块（`oh-package.json5` name `happy-wire`、`module.json5` name `happy_wire`），首批移植 `AuthRequestBody / AuthRequestResponse / Session / SessionListResponse`。根 `build-profile.json5` 注册 `happy_wire` 模块，Stage 通过 `import { ... } from 'happy-wire'` 消费。
6. **会话列表骨架**：`service/session/sessionList.ets` 包 `fetchSessions()` 调 `/v1/sessions`。`HomePage.ets` 用 `List + ForEach + @ObjectLink` 渲染 active dot / id 截断 / "metadata pending" 占位 / `updatedAt`。loading / error / empty / list 四状态完整。
7. **ArkTS strict warning 清零**：所有 "Function may throw exceptions" 警告通过 JSDoc `@throws { BusinessError }` 链式标注消除。

### Phase 1a 技术债（交给后续里程碑）

- **DEV_TOKEN bootstrap hack**：`Stage/src/main/ets/service/auth/authStore.ets` 里有一个 `DEV_TOKEN: string` 常量，非空时 `initAuth` 跳过 QR 流程直接伪造 credentials 入库。用于 1a 真机验证绕开登录。**commit 前必须清空**（文件内已有行内警告）。  
  真正可用的 QR login 需 LoginPage 加 QR 渲染（见下一条），否则 DEV_TOKEN 是 1a 的替身。
- **QR 码渲染缺失**：account auth 流程的 `happy:///account?<base64url>` URL 只能通过相机扫码被 happy-app 识别（`useConnectAccount.onModernBarcodeScanned`；无手动输入 UI，无 deep link route）。LoginPage 目前只显示 URL 文本字符串，扫码走不通。Phase 2 前补 QR 渲染（HarmonyOS 有官方 `QRCode()` 组件）。
- **PoC-A3（AES-256-GCM 互操作）未做**：`/v1/sessions` 响应里每个 Session 的 `metadata` / `agentState` 是 AES-GCM 密文（经 `rn-encryption` 私有布局：`[0x00 version byte || AES-GCM ciphertext]`），UI 显示"metadata pending"。解开后才能显示 path / host / summary。工作量独立，和 1b/1e 可并行。

## Phase 2+ — 未规划

UI 页面、WebRTC 音频采集/播放、推送（HMS Push）、支付等，等 Phase 1 推进后再分支。

## 仓库结构速查

- `docs/` — 调研文档 + 本进度表
- `packages/nacl/` — PoC-A2 独立 NAPI 模块源码（源头），同一份源码内嵌进 Stage/ 用于真机验证（1e 将抽成真 HAR）
- `packages/wire/` — `happy-wire` HAR 模块，纯 ArkTS 协议类型（authQR + session list 已移，其余随 1b / PoC-A3 扩充）
- `Stage/` — DevEco entry 模块（HAP），按 MVVM 分层：`ets/pages ets/service ets/api ets/storage ets/common ets/webrtc ets/stageability`
- `libs/webrtc-1.0.0.har` — vendored `@ohos/webrtc`（绕开 ohpm 镜像超时）
- `tests/vectors/` — tweetnacl-js 生成的 secretbox / box / sign 对拍 fixture

## 更新纪律

- 每次 PoC/里程碑推进后，改这一个文件
- 调研/设计类新文档可以新开（编号如 `02-*.md`），但"进度状态"只走本文件
- commit message 里写技术细节；本文件写**现在到哪了、下一步做什么**，要能让翻开它的人 3 分钟对齐
