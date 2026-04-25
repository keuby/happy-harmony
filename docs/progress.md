# happy-harmony 进度

HarmonyOS Next 原生 ArkTS 版 slopus/happy。本文件是跨阶段进度的**单一可信来源**——每完成里程碑更新这里，不新建状态文档。

> 最后更新：2026-04-25（1e nacl HAR 化真机通）

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
| **1f** Restore with Secret Key | `/v1/auth` 自助换 token，替换 DEV_TOKEN 作为主登录入口 | ✅ 真机端到端 |
| **PoC-A3** AES-256-GCM 互操作 | `@ohos.security.cryptoFramework` + BIP32 HMAC deriveKey，解 session metadata 并渲染到 HomePage | ✅ 真机端到端 |
| **1b** LiveKit 客户端 | WebSocket + protobuf v9 信令层 → `@ohos/webrtc` | ⏳ 待开工 |
| **1d** `happy-wire` 协议 | Zod → ArkTS 类型移植（authQR + session + /v1/auth 已移，messages / realtime 待补） | ⏳ 部分（随 1b/消息解密逐步扩） |
| **1e** nacl HAR 化 | `packages/nacl` 升级为真正的 HAR 模块（带 native 编译），替换 `Stage/` 里的双份同步副本 | ✅ 真机端到端 |

1a / 1c / 1e / 1f / PoC-A3 已完结。剩余 1b / 1d 可并行推进——1d 随 1b / 消息解密增量扩。

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

### Phase 1a 技术债（已还清 / 留存）

- ~~**DEV_TOKEN bootstrap hack**~~ ✅ 2026-04-25 清除。登录改由 **Restore with Secret Key** 路径承担（见下）。
- ~~**QR 码渲染缺失**~~ ✅ 2026-04-25 LoginPage 加 `QRCode()` 组件（220×220，token 配色）。扫码链路**未打通**：happy-app 的 Account 通道只有相机入口无"粘贴 URL" UI；HarmonyOS 生态可扫码的 happy 客户端尚无（卓易通跑 happy-android 调不起相机）。当前仅保留 UI 以便未来接 Terminal auth 或其他 approver 渠道。
- ~~**PoC-A3（AES-256-GCM 互操作）**~~ ✅ 2026-04-25 完结，见下。

### Phase 1f — Restore with Secret Key ✅ 完结

> 2026-04-25 真机端到端：粘贴 `XXXXX-XXXXX-…` secret → Log in → 1.8 s 进 HomePage → 拉到 2 条 sessions。

happy 账户的根密钥是 32 字节 account secret；`authGetToken(secret)` 用 ed25519 challenge-sign 直接 self-service 换 token，**不需要 approver**。对标 happy-app `/restore/manual`。Stage 加一条登录入口：

- `Stage/src/main/ets/common/crypto/secretKeyBackup.ets` — base32 解码 + `normalizeSecretKey`（兼容 `XXXXX-XXXXX-…` 分组格式、0/1/8/9 OCR 纠错、base64 回退）。只做解码方向（Stage 不展示 secret）。
- `Stage/src/main/ets/service/auth/authChallenge.ets` — 复用 PoC-A2 的 `cryptoSignKeypairFromSeed` + `cryptoSignDetached`；1c 预留的 sign-keypair + detached-sig NAPI surface 终于有真实调用者。
- `Stage/src/main/ets/service/auth/authGetToken.ets` — POST `/v1/auth`，公钥 / 挑战 / 签名走**标准 base64**（和服务端 `privacyKit.decodeBase64` 一致，非 base64url）。
- `service/auth/authStore.ets` 加 `loginWithSecret(input)`，与 QR 流程共用 `authenticating` 态；LoginPage 按 `pendingPublicKey` 是否为空分派 UI。
- `packages/wire/src/main/ets/auth.ets` 加 `AuthLoginBody / AuthLoginResponse` wire schema。

**为什么这条路比完整 QR approve 更合适做主登录路径**：零外部依赖（不需要"另一台已登录设备"），和 happy-app 的 `/restore/manual` 行为等价，是官方的账户恢复通道而非 hack。扫码入口未来可随 Phase 2 补齐。

### PoC-A3 — session metadata 解密 ✅ 完结

> 2026-04-25 真机端到端：HomePage 上 2 条 session 的 `metadata pending` 占位被 `watchtower` + `host · /Users/kchen/Workspace/watchtower` 替代。

happy-server `/v1/sessions` 里每条 session 的 `metadata` / `agentState` 是**每 session 独立 AES-GCM 加密**。完整 key 链（V2 路径）：

```
account secret  ──HMAC-SHA512("Happy EnCoder Master Seed")──►  contentDataKey
contentDataKey  ──libsodium crypto_box_seed_keypair──►         contentKeyPair (X25519)
session.dataEncryptionKey (0x00 || ephPk(32) || nonce(24) || crypto_box_easy body(48))
                ──crypto_box_open_easy with contentKeyPair.secretKey──►  per-session dataKey
session.metadata (0x00 || iv(12) || ct || tag(16))
                ──AES-256-GCM decrypt with dataKey──►  JSON Metadata
```

V1 legacy fallback（`dataEncryptionKey === null`）走 NaCl `secretbox_open_easy(nonce || mac || ct, masterSecret)`。当前真机两条 session 都是 V2 路径，V1 分支保留以对齐上游。

**新增**：
- `common/crypto/hmacSha512.ets` — 薄包 `cryptoFramework.createMac('SHA512')`
- `common/crypto/deriveKey.ets` — 移植 happy-app 的 BIP32-style 键树派生（`root("<usage> Master Seed", seed)` → 多层 `child(chainCode, index)`）
- `common/crypto/aesGcm.ets` — `cryptoFramework.createCipher('AES256|GCM|NoPadding')` + 手动 unpack `0x00 || iv || ct || tag`（鸿蒙的 GcmParamsSpec 要求单独传 authTag；JCE 的 `doFinal(ct||tag)` 风格在这里不适用）
- `service/session/sessionDecrypt.ets` — `SessionDecryptor.create(masterSecret)` 构造时预派生 contentKeyPair；逐 session `decrypt()` 返回 `DecryptedSession { session, metadata: SessionMetadata | null }`
- HomePage 主标题 = `basename(path)` 项目名；次要行 = `summary.text` 或 `host · path` fallback

**关键 bug（1c 的债）**：`CryptoBoxKeypairFromSeed` NAPI 原实现是 tweetnacl 风格 `sk = seed`，和 happy-app 用的 **libsodium `crypto_box_seed_keypair`（`sk = SHA-512(seed)[0..32]`）**不兼容。跨 app 的 box 一直不通只是 1c fixture 也是 tweetnacl 侧所以互相对称看不出来。改成 libsodium 风格后 contentKeyPair 的 pk 才对得上服务端存的 `dataEncryptionKey`。修复同步到 `Stage/src/main/cpp/napi_init.cpp` + `packages/nacl/src/cpp/napi/nacl_napi.cpp` 双份源。1e 同步把 `tests/vectors/box.json` fixture 改成 libsodium 侧，generator 加 `libsodiumBoxSeedKeypair()` helper。

### Phase 1e — nacl HAR 化 ✅ 完结

> 2026-04-25 真机端到端：HAR build 出 89 KB `libnacl.so` 装进 hap，Stage 删 cpp 副本后登录 + 解密 metadata 全绿。

`packages/nacl` 重组为标准 HAR 模块，对齐 `packages/wire` 的结构：

```
packages/nacl/
  hvigorfile.ts          (harTasks)
  build-profile.json5    (externalNativeOptions → cpp/CMakeLists.txt, abiFilters)
  oh-package.json5       (main: ets/Index.ets, deps libnacl.so 自指 type stubs)
  src/main/
    module.json5         (type: "har", name: happy_nacl)
    ets/Index.ets        (named re-export from libnacl.so + 常量)
    cpp/
      CMakeLists.txt     (输出 libnacl.so)
      tweetnacl/         (源)
      napi/nacl_napi.cpp
      types/libnacl/     (Index.d.ts + oh-package.json5)
```

根 `build-profile.json5` 注册 `happy_nacl` 模块；Stage `oh-package.json5` 加 `"happy-nacl": "file:../packages/nacl"` —— ohpm 透传 `libnacl.so` type 依赖给 Stage，不需要再显式 dep。Stage 端 `import nacl from 'libnacl.so'` 不变，删 `Stage/src/main/cpp/` + `externalNativeOptions` 块。

`tests/vectors/box.json` 用 generator 新加的 `libsodiumBoxSeedKeypair()` helper 重生 — keypair 的 `publicKeyHex` / `secretKeyHex` 都换成 libsodium 派生值（之前对的是 tweetnacl 派生值，跟现在的 NAPI 不再一致）。

## Phase 2+ — 未规划

UI 页面、WebRTC 音频采集/播放、推送（HMS Push）、支付等，等 Phase 1 推进后再分支。

## 仓库结构速查

- `docs/` — 调研文档 + 本进度表
- `packages/nacl/` — `happy-nacl` HAR 模块，build 出 `libnacl.so` 给消费者
- `packages/wire/` — `happy-wire` HAR 模块，纯 ArkTS 协议类型（authQR + session + /v1/auth 已移，其余随 1b 扩充）
- `Stage/` — DevEco entry 模块（HAP），按 MVVM 分层：`ets/pages ets/service ets/api ets/storage ets/common`
- `libs/webrtc-1.0.0.har` — vendored `@ohos/webrtc`（绕开 ohpm 镜像超时）
- `tests/vectors/` — tweetnacl-js 生成的 secretbox / box / sign 对拍 fixture

## 更新纪律

- 每次 PoC/里程碑推进后，改这一个文件
- 调研/设计类新文档可以新开（编号如 `02-*.md`），但"进度状态"只走本文件
- commit message 里写技术细节；本文件写**现在到哪了、下一步做什么**，要能让翻开它的人 3 分钟对齐
