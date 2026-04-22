# LiveKit/WebRTC on HarmonyOS Next 可行性调研

> 调研日期：2026-04-22
> 目标：评估 slopus/happy 从 RN+Expo 迁到纯血鸿蒙 Next 原生 ArkTS 后，实时音视频（当前栈：LiveKit + ElevenLabs ConvAI）的可行性。

## 结论（一句话 Go/No-Go）

**谨慎 Go，首选方案 C（ArkWeb WebView 承载 LiveKit web SDK）作为落地版本，方案 A（自移植 libwebrtc + 自写 LiveKit 客户端）作为 6-12 个月后的原生替换路径。方案 B（替换为 HMS RTC / 声网）在 happy 的场景下不成立——因为服务端是 ElevenLabs ConvAI 托管的 LiveKit，替换意味着放弃 ElevenLabs。**

关键事实：
- 纯血鸿蒙 Next 目前**没有官方 WebRTC Kit**，华为文档中未发现"HMS RTC Kit"这一产品。
- ArkWeb（基于 Chromium 114→132）**部分支持 WebRTC**：`getUserMedia` 已有官方文档，但 `RTCPeerConnection` 的完整度在社区反馈中"不完整、有 bug"，需实测验证。
- 社区已有 **OpenHarmony-SIG/ohos_webrtc** 仓库（原 Gitee，已迁至 GitCode），是 libwebrtc 的官方移植，BSD-3 许可，但对 **HarmonyOS Next** 的明确适配未见声明；已知 1 个独立开发者在 OpenHarmony 4.0 上完成功能性移植并跑通 1080p@30fps。
- 声网 SDK（@shengwang/rtc-full）在鸿蒙 Next 上稳定可用（v4.4.2, 2024-11），但它是**私有协议不是 LiveKit 协议**，换它等于换后端。
- happy 当前用 LiveKit 是因为 **ElevenLabs ConvAI 的底层传输就是 LiveKit**（见 `voiceRoutes.ts:154-170`：从 ElevenLabs 拿到的 `conversationToken` 就是 LiveKit JWT），所以不能换到其他 RTC 厂商，否则丢失 ElevenLabs 语音智能体能力。

---

## 1. HarmonyOS Next WebRTC 原生能力现状

### 1.1 华为官方 Kit 层面

| Kit | WebRTC 相关能力 | 能否组合实现 WebRTC | 来源 |
|---|---|---|---|
| **ArkWeb (@ohos.web.webview)** | Chromium 内核 WebView，文档确认支持 `navigator.mediaDevices.getUserMedia`，HTTPS/localhost + `onPermissionRequest` + `ohos.permission.CAMERA/MICROPHONE` | **是（通过 WebView 内 web SDK）** | OpenHarmony 文档 `web-rtc.md` |
| **Camera Kit (@ohos.multimedia.camera)** | 摄像头采集、YUV/SurfaceID | 作为 WebRTC 采集源需桥接 | 华为 developer.huawei.com |
| **Audio Kit (@ohos.multimedia.audio)** | 麦克风采集、AudioRenderer | 作为 WebRTC 音频源需桥接 | 华为 developer.huawei.com |
| **AVCodec Kit (@ohos.multimedia.media)** | 硬编硬解 H.264/H.265/AAC/Opus | 可用，但不是 WebRTC 原语 | 华为 developer.huawei.com |
| **Network Kit** | TCP/UDP Socket、WebSocket | 信令可用；UDP 打洞/STUN 需自行实现 | 华为 developer.huawei.com |
| **NDK / NAPI** | C/C++ 原生层，可加载 .so | libwebrtc 理论可跑 | 华为 developer.huawei.com |
| **HMS RTC Kit** | **未发现**——华为未推出官方实时音视频 Kit | N/A | 搜索未命中 |

**结论：没有官方 RTCPeerConnection-like API。** WebRTC 的 ICE/DTLS-SRTP/SDP 协商层完全需要自己实现或移植 libwebrtc。

### 1.2 ArkWeb WebRTC 实测现状（关键）

- **官方文档确认支持**：OpenHarmony 官方 `web-rtc.md` 文档给出 `getUserMedia` 示例，要求在 `module.json5` 声明 `ohos.permission.CAMERA` 和 `ohos.permission.MICROPHONE`，并在 `onPermissionRequest` 回调中授权。
- **社区实测反馈**：multiple CSDN / itying 帖子反映 HarmonyOS Next 上 `navigator.mediaDevices.getUserMedia` 有时返回 `undefined`，被怀疑是 ArkWeb 内核版本 WebRTC 编译选项没开全。
- **ArkWeb 内核版本**：HarmonyOS 5.x 版 ArkWeb 基于 Chromium 114；HarmonyOS 6.0 升级到 Chromium 132（按公开资料）。Chromium 114/132 本身都完整支持 `RTCPeerConnection` + `DataChannel` + `DTLS-SRTP`，**关键是华为裁剪编译时是否保留 WebRTC 模块**——这一点**未能从官方文档确认**，需用真机跑 `webrtc.github.io/samples` 验证。

### 1.3 社区 libwebrtc 移植

| 仓库 | 地址 | 状态 | 可用性 |
|---|---|---|---|
| **OpenHarmony-SIG/ohos_webrtc** | gitee.com/openharmony-sig/ohos_webrtc（已归档，迁至 GitCode 同名）| 38 stars / 33 forks，OpenHarmony SIG 官方孵化，BSD-3 | 有构建脚本 + OHOS Audio adapter；未见 ohpm 包；未见 HarmonyOS Next 的明确验收 |
| **OpenHarmony-SIG/fluttertpc_flutter_webrtc** | gitee 同上 | flutter-webrtc 的 OHOS 端口 | 仅服务于 Flutter，ArkTS 原生不可直接用 |
| **独立开发者 OpenHarmony 4.0 WebRTC 移植**（CSDN Cowboy1929） | 无公开代码仓库 | 已实现 PeerConnection + H264 硬编 + 3A + GL 渲染，1080p@30fps 稳定 | 闭源，不可直接用；证明技术可行 |
| **花不成/oh_webRTC**（gitee.com/han_jin_fei/oh_web-rtc）| Gitee 个人仓库 | 早期实验性质 | 参考价值 |

**结论：libwebrtc 在 OpenHarmony 上"跑得通"已被证明，但没有一个成熟、有维护、发布到 ohpm 的现成包。** 直接拿 ohos_webrtc 源码自己编译是可走的路，但工作量不小（libwebrtc 60+ 依赖库，camera/audio/codec 需要重新适配 HarmonyOS Next 的 API 而非 OpenHarmony 4.0 的 API，Next 的 Camera/Audio Kit 接口有变化）。

---

## 2. LiveKit 客户端在鸿蒙 Next 复现可行性

### 2.1 LiveKit 客户端的技术分解

按官方 Client Protocol 文档，LiveKit client SDK 由三层组成：

| 层 | 职责 | 在鸿蒙 Next 上的难度 |
|---|---|---|
| **信令层** | WebSocket + Protobuf（协议版本 9），消息包括 `JoinResponse`、`AddTrackRequest`、`UpdateSubscription`、`TrickleRequest`、`SignalRequest/Response` | **低**。ArkTS 有 `@ohos.net.webSocket` 和 protobuf-ts，纯 TS 即可 |
| **WebRTC 传输层** | 最多 2 个 `PeerConnection`（publisher + subscriber）+ DataChannel + ICE trickle + DTLS-SRTP | **高**。无 HarmonyOS 原生 RTCPeerConnection API |
| **媒体管线** | 音频采集/编码/渲染、视频采集/编码/渲染、回声消除 | **中**。Camera/Audio/AVCodec Kit 有现成能力，但要接入 libwebrtc 数据流需写 NAPI 桥 |

**LiveKit 没有 non-WebRTC fallback**，媒体传输完全依赖 WebRTC 栈。

### 2.2 happy 项目对 LiveKit 的实际使用范围

从 `happy/packages/happy-app/package.json` + `happy-server/sources/app/api/routes/voiceRoutes.ts` 分析：

- 只用 **音频通话（TTS/STT）**，无视频。
- 服务端 `POST /v1/voice/conversations` 从 **ElevenLabs ConvAI** 获取 `conversationToken`（即 LiveKit JWT），客户端用 `livekit-client` 连到 ElevenLabs 托管的 LiveKit 房间。
- 关键依赖：`@livekit/react-native@^2.9.0`、`@livekit/react-native-webrtc@^137.0.0`、`livekit-client@^2.15.4`。
- **这意味着 LiveKit 是 ElevenLabs 的底层——换掉 LiveKit 就等于放弃 ElevenLabs**，后端不只是换一套 SFU 那么简单。

### 2.3 非官方 LiveKit HarmonyOS 客户端

**未找到**。GitHub、Gitee、GitCode 上搜不到 "livekit" + "harmony/ohos" 的客户端仓库。仅有一个旁证：`livekit/client-sdk-flutter` issue #733 提到 Huawei nova 11 (HarmonyOS 4.2, 旧版 AOSP 兼容) 的视频编码问题，与纯血 Next 无关。

---

## 3. 方案对比

| 方案 | 描述 | 工作量 | 风险 | 对后端影响 | ElevenLabs 兼容 |
|---|---|---|---|---|---|
| **A. 自移植 libwebrtc + 自写 LiveKit client（ArkTS + NAPI）** | 基于 OpenHarmony-SIG/ohos_webrtc 适配 HarmonyOS Next API，上层 ArkTS 写 LiveKit 信令 + protobuf，通过 NAPI 暴露 PeerConnection | **8-14 人月**（2-3 人并行 4-6 月）：移植 ohos_webrtc 到 Next API 4 人月 + 接 Camera/Audio Kit 2 人月 + ArkTS LiveKit 协议层 2 人月 + 联调 + QA 2-4 人月 | **高**。libwebrtc 升级维护成本高；华为 Camera/Audio Kit 与 libwebrtc 的 AudioDeviceModule 接口差异大；上架合规（加密库）| 零影响 | ✅ 兼容 |
| **B. 替换为声网/HMS RTC + 改后端** | 客户端用 @shengwang/rtc-full，后端放弃 ElevenLabs ConvAI，自建 STT/TTS/LLM 管线 | **20+ 人月**：后端重构语音智能体（ASR + LLM turn-taking + TTS + 打断 + 上下文）10-15 人月，客户端接入 1 人月，多端一致性维护 + 双栈并行 5+ 人月 | **极高**。ElevenLabs ConvAI 的 VAD/打断/音色克隆/多轮状态是核心产品能力，自建至少落后 1-2 代 | **重构**。放弃 ElevenLabs，自建语音 agent 栈 | ❌ 不兼容 |
| **C. ArkWeb WebView 承载 LiveKit web SDK** | ArkTS 壳 + 一个全屏不可见的 ArkWeb 组件加载 H5 页面，H5 内跑 `livekit-client` + `@livekit/client-sdk-js`，通过 JSBridge 与 ArkTS 通信状态 | **2-4 人月**：ArkWeb WebRTC 真机验证 0.5 人月 + JSBridge 设计 0.5 人月 + H5 客户端 1 人月 + 权限/后台/音频路由联调 1-2 人月 | **中**。依赖 ArkWeb WebRTC 完整度（需真机验证 `RTCPeerConnection`）；后台保活、锁屏通话、蓝牙耳机切换需要额外 workaround | 零影响 | ✅ 兼容 |

---

## 4. 推荐路线与下一步

### 4.1 推荐路线（两阶段）

**阶段 1（0-3 个月）：方案 C 做 MVP 上架**
- **先验证**：在真机 HarmonyOS Next（建议 5.0 + 6.0 各一台）上跑 `https://webrtc.github.io/samples/src/content/peerconnection/pc1/`，如果能建立本地 peer connection，说明 ArkWeb 的 WebRTC 完整度够用。
- **如果验证通过**：ArkTS 写壳 + ArkWeb 加载一个为鸿蒙特化的 H5 语音页（只保留 LiveKit + ElevenLabs 客户端逻辑），ArkTS 通过 JSBridge 同步连接状态、VU meter、通话时长、断线事件。注意 `BackForwardCache` 在音频会话时关闭，锁屏时依靠后台任务（`ohos.backgroundTaskManager`）保活音频。
- **如果验证失败**：直接跳到阶段 2，阶段 1 时间用于 PoC。

**阶段 2（3-12 个月）：方案 A 原生化**
- 等 OpenHarmony-SIG/ohos_webrtc 对 Next API 的适配成熟，或在内部基于其 fork 完成适配。
- 上层写 TypeScript 的 LiveKit 客户端（可直接 fork livekit/client-sdk-js，把 `RTCPeerConnection` 依赖替换为 NAPI 导出的壳），避免重新实现信令。
- 发布为内部 ohpm 包。

### 4.2 立即可执行的 3 个调研动作

1. **真机 PoC（2 天）**：拿一台 HarmonyOS Next 5.x 设备，ArkWeb 加载 WebRTC 官方 samples，验证 `getUserMedia` + `RTCPeerConnection` + loopback + DataChannel 能否工作，结果直接决定阶段 1 走方案 C 还是直接上方案 A。
2. **ohos_webrtc 编译验证（3 天）**：在 HarmonyOS Next NDK 下尝试编译 OpenHarmony-SIG/ohos_webrtc，确认构建产物能否被 DevEco Studio 打包进 .hap。
3. **LiveKit 协议最小客户端原型（1 周）**：用 ArkTS 先把信令层跑通（WebSocket + protobuf + JoinResponse），不涉及 WebRTC，作为方案 A 的前置验证，风险最低。

### 4.3 风险提示

- **华为应用市场上架审核**：libwebrtc 含有加密组件（DTLS-SRTP），需要商用密码自评估或通过华为的合规通道，提前与华为对接。
- **ElevenLabs 侧兼容性**：ElevenLabs 的 LiveKit 协议版本跟随其服务端升级，客户端如果自研需要持续跟 LiveKit 协议版本（当前 v9），建议订阅 livekit/protocol releases。
- **后台/锁屏/音频焦点**：鸿蒙 Next 的后台策略比 Android 严格，持续音频会话需要 `ohos.permission.KEEP_BACKGROUND_RUNNING` + 分布式音频任务声明，方案 C 在 WebView 里拿这些能力可能受限，是方案 C 最大的未知数。

---

## 5. 参考资料

**LiveKit 协议与 SDK**
- [LiveKit Client Protocol](https://docs.livekit.io/reference/internals/client-protocol/)
- [LiveKit JS Client SDK v2.18.1](https://docs.livekit.io/reference/client-sdk-js/)
- [livekit/protocol（protobuf 定义）](https://github.com/livekit/protocol)
- [livekit/client-sdk-js](https://github.com/livekit/client-sdk-js)
- [LiveKit SFU 内部文档](https://docs.livekit.io/reference/internals/livekit-sfu/)

**HarmonyOS Next / ArkWeb**
- [ohos.web.webview 官方文档](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V5/js-apis-webview-V5)
- [OpenHarmony ArkWeb WebRTC 官方文档（getUserMedia）](https://github.com/openharmony-rs/openharmony-docs/blob/master/zh-cn/application-dev/web/web-rtc.md)
- [ArkWeb 开发综合指南](https://dev.to/moyantianwang/comprehensive-guide-to-harmonyos-arkweb-development-45aj)
- [ArkWeb WebRTC 视频会议实战（CSDN）](https://blog.csdn.net/qq_39652397/article/details/142854189)
- [ArkWeb getUserMedia 未定义问题讨论（itying）](https://bbs.itying.com/topic/6838d58f4715aa008847b1f6)
- [Hacking Chromium on OpenHarmony](https://medium.com/kodegood/hacking-chromium-on-openharmony-97d135792151)

**OpenHarmony libwebrtc 移植**
- [OpenHarmony-SIG/ohos_webrtc (Gitee, 已归档)](https://gitee.com/openharmony-sig/ohos_webrtc)
- [OpenHarmony-SIG/ohos_webrtc (GitCode, 新地址)](https://gitcode.com/OpenHarmony-SIG/ohos_webrtc/blob/master/docs/ohos/webrtc_build.md)
- [OpenHarmony 4.0 WebRTC 移植实战（CSDN）](https://blog.csdn.net/Cowboy1929/article/details/142351719)
- [鸿蒙 Next webrtc 库移植讨论（itying）](https://bbs.itying.com/topic/674069a5cccbe300e4eece3c)
- [OpenHarmony-SIG/fluttertpc_flutter_webrtc](https://gitee.com/openharmony-sig/fluttertpc_flutter_webrtc)

**第三方 RTC SDK（鸿蒙 Next）**
- [声网 Agora HarmonyOS 快速开始](https://doc.shengwang.cn/doc/rtc/harmonyos/get-started/quick-start)
- [声网 Agora HarmonyOS 发版说明](https://doc.shengwang.cn/doc/rtc/harmonyos/overview/release-notes)
- [融云上线 HarmonyOS NEXT SDK](https://blog.rongcloud.cn/?p=10970)
- [即构 ZEGO 上线 HarmonyOS NEXT SDK](https://www.nxrte.com/zixun/42753.html)
- [百家云 BRTC HarmonyOS 发版说明](https://docs.baijiayun.com/rtc/release/HarmonyOS.html)
- [火山引擎 HarmonyOS Next RTC 文档](https://www.volcengine.com/docs/6348/1433813)

**LiveKit vs Agora / 迁移成本**
- [LiveKit vs Agora 成本分析](https://www.forasoft.com/blog/article/livekit-vs-agora-cost-analysis)
- [LiveKit vs Twilio vs Agora (2026)](https://sheerbit.com/livekit-vs-twilio-vs-agora-which-real-time-platform-should-you-choose/)
- [8 Best LiveKit Alternatives](https://getstream.io/blog/livekit-alternatives/)

**happy 项目本地文件（LiveKit 使用范围依据）**
- `/Users/kchen/Workspace/remote-working/happy/packages/happy-app/package.json` — LiveKit 依赖声明
- `/Users/kchen/Workspace/remote-working/happy/packages/happy-server/sources/app/api/routes/voiceRoutes.ts` — 证明 LiveKit token 来源于 ElevenLabs ConvAI
