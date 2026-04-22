# libsodium on HarmonyOS Next 调研

> 调研日期：2026-04-22
> 目标：评估 slopus/happy 从 RN+Expo 迁到纯血鸿蒙 Next 原生 ArkTS 后，E2E 加密依赖（libsodium）的实现路径。

## 结论

**推荐方案 α（混合方案）：AES-256-GCM / SHA-512 / HMAC-SHA512 / 随机数走 HarmonyOS CryptoArchitectureKit，NaCl 家族（box/secretbox/sign）走 NAPI 封装 TweetNaCl 的 C 源码**（或直接复用 `OpenHarmony-SIG/libsodium` 的 C 产物）。

**一句话理由**：happy 实际只用到 libsodium 中 NaCl 子集的 8 个入口（`crypto_box_*`、`crypto_secretbox_*`、`crypto_sign_*`），且 happy-agent 已用 tweetnacl 完整复现并跑通；鸿蒙官方 Kit 覆盖不了 Curve25519/Ed25519/XSalsa20-Poly1305 这三件 NaCl 核心原语，但复现它们的最小 C 代码量极小（TweetNaCl 整库约 700 行 C），NAPI 包装 1–2 周可完成，远比"全量 libsodium C 源码交叉编译"省事，也比"纯 ArkTS 复写"稳妥。

---

## 1. happy 实际使用的 libsodium 函数清单

来源：`grep -E "sodium\.|crypto_box|crypto_secretbox|crypto_sign|crypto_aead|crypto_generichash|crypto_pwhash|crypto_kx|randombytes" packages/` 全量扫描结果。

| libsodium 符号 | 用途 | 调用位置（绝对路径） |
|---|---|---|
| `crypto_box_seed_keypair` | 从 32B 种子派生 X25519 keypair | `/Users/kchen/Workspace/remote-working/happy/packages/happy-app/sources/encryption/libsodium.ts:5`；`.../sync/encryption/encryption.ts:20`；`.../sync/encryption/encryptor.ts:52`；`.../auth/authQRStart.ts:15` |
| `crypto_box_keypair` | 生成临时 X25519 keypair（ephemeral） | `.../encryption/libsodium.ts:9` |
| `crypto_box_easy` / `crypto_box_open_easy` | 公钥认证加密（X25519 + XSalsa20-Poly1305） | `.../encryption/libsodium.ts:11,29` |
| `crypto_box_NONCEBYTES` / `crypto_box_PUBLICKEYBYTES` | 常量（24 / 32） | `.../encryption/libsodium.ts:10,24,25,26` |
| `crypto_secretbox_easy` / `crypto_secretbox_open_easy` | 对称认证加密（XSalsa20-Poly1305） | `.../encryption/libsodium.ts:38,50` |
| `crypto_secretbox_NONCEBYTES` | 常量（24） | `.../encryption/libsodium.ts:37,46,47` |
| `crypto_sign_seed_keypair` | 从种子派生 Ed25519 keypair | `.../auth/authChallenge.ts:5` |
| `crypto_sign_detached` | Ed25519 detached 签名 | `.../auth/authChallenge.ts:7` |
| `sodium.ready` | WASM/native 初始化等待 | `.../app/_layout.tsx:224` |

**未用到的"重型"原语**（grep 全零命中）：

- `crypto_aead_xchacha20poly1305_ietf_*` — **未用**
- `crypto_generichash`（Blake2b）— **未用**
- `crypto_pwhash`（Argon2id）— **未用**
- `crypto_kx`（Key Exchange）— **未用**
- `randombytes_buf` — **未用**（随机数走 `expo-crypto` 的 `getRandomBytes`，鸿蒙端可换 `@ohos.security.cryptoFramework.createRandom()`）

**协议侧交叉验证**（决定性证据）：

- `/Users/kchen/Workspace/remote-working/happy/packages/happy-agent/src/encryption.ts` 用 **tweetnacl** 单一库完整复现了 happy-app 所有 libsodium 调用点的语义，逐行对应：`tweetnacl.box.keyPair`、`tweetnacl.box.keyPair.fromSecretKey`（line 79）、`tweetnacl.secretbox`（line 124）、`tweetnacl.secretbox.open`（line 135）、`tweetnacl.sign.keyPair.fromSeed`（line 169）、`tweetnacl.sign.detached`（line 173）、`tweetnacl.box` / `tweetnacl.box.open`（line 186/203）。
- `/Users/kchen/Workspace/remote-working/happy/packages/happy-server/sources/app/api/routes/authRoutes.ts:18-225` 服务端验签也只用 `tweetnacl.sign.detached.verify` + `tweetnacl.box.publicKeyLength`。
- `/Users/kchen/Workspace/remote-working/happy/packages/happy-wire/src/` 只有 Zod schema（数据结构定义），不包含任何加密算法选择，协议层不约束算法实现来源。

**结论**：happy E2E 协议的 ciphersuite 精确等于「NaCl 子集 + AES-256-GCM + HMAC-SHA512」。鸿蒙端只需要复现这个集合，不需要全量 libsodium。

附：协议里的其他加密原语：

| 原语 | 用途 | 位置 |
|---|---|---|
| `AES-256-GCM` | 新版 session/machine 数据的 AES256Encryption | `.../encryption/aes.ts` → `rn-encryption` 原生模块；`.../happy-agent/src/encryption.ts:85-117` |
| `HMAC-SHA512` | 分层 key derivation（自研 BIP32-like KDF） | `.../encryption/hmac_sha512.ts`；`.../encryption/deriveKey.ts`；`.../happy-agent/src/encryption.ts:36-72` |
| `SHA-512` | `deriveContentKeyPair` 里把 seed 做 SHA-512[0:32] 再喂给 box seed | `.../happy-agent/src/encryption.ts:77` 注释明确："libsodium's crypto_box_seed_keypair does SHA-512(seed)[0:32] internally"——**这是协议复现的关键细节，必须字节对齐** |

---

## 2. HarmonyOS CryptoArchitectureKit 覆盖度对照表

注：Huawei 官方文档站是 JS 渲染的 SPA，WebFetch 无法直接抓正文；下表结合 Huawei 站搜索结果标题（developer.huawei.com 侧）、OpenHarmony-SIG 仓库和 dev.to/Medium 社区二手资料交叉整理，精确到具体 API 名的条目已在来源列标注。拿不到原文确证的项标注「待官方文档核验」。

| libsodium 函数 | Harmony Kit 对应 API | 是否等价 | 备注 |
|---|---|---|---|
| `crypto_box_*`（X25519 + XSalsa20-Poly1305 的 AE 包装） | **无直接等价** | 否 | Kit 提供 X25519 密钥协商（`createKeyAgreement('X25519')`，见 [Key Agreement Using X25519 (C/C++)](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/crypto-key-agreement-using-x25519-ndk)）；但 happy 用的是"XSalsa20-Poly1305 + 临时 X25519 + 固定 HSalsa20 KDF"的固定包装（NaCl 定义），Kit 不提供；即便用 X25519+AEAD 也改了 ciphersuite，会与 happy-server 和 happy-agent 无法互通 |
| `crypto_secretbox_*`（XSalsa20-Poly1305） | **无** | 否 | Kit 支持 AES/SM4 和 ChaCha20-Poly1305（待官方文档核验），但 **不支持 XSalsa20 / XChaCha20**；协议不能切 |
| `crypto_sign_*`（Ed25519） | **待官方文档核验** | 待核验 | Huawei 站搜索结果列出 [Signing and Signature Verification Development](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/crypto-sign-sig-verify-dev-V14)，但全网暂未搜到 ArkTS Ed25519 的具体用例；从 SIG 仓库 `openharmony-sig/libsodium` 的 `sign/` 目录看底层 Ed25519 代码是齐的，官方 Kit **很可能**只暴露 RSA/ECDSA/SM2，Ed25519 覆盖度需在实机验证；**即便 Kit 原生支持 Ed25519，签名/验签实现在 Ed25519 规范下是确定性字节输出，可以替换，不影响互操作** |
| `crypto_aead_xchacha20poly1305_ietf_*` | **无** | N/A | happy 未使用 |
| `crypto_generichash`（Blake2b） | **无**（Kit 仅 SHA-1/224/256/384/512，SM3） | N/A | happy 未使用 |
| `crypto_pwhash`（Argon2id） | **无**；Kit 提供 [PBKDF2](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/crypto-key-derivation-using-pbkdf2)、HKDF | N/A | happy 未使用 |
| `crypto_kx` | **无** | N/A | happy 未使用 |
| `randombytes_buf` | `cryptoFramework.createRandom().generateRandomSync(n)` | 是 | 直接替换 |
| `crypto_box_seed_keypair` 内部 SHA-512 处理 | `cryptoFramework.createMd('SHA512')` | 是 | 协议复现关键点，见 `happy-agent/src/encryption.ts:77` |
| **外围原语（非 libsodium 但 happy 用到）** | | | |
| AES-256-GCM | `cryptoFramework.createCipher('AES256|GCM|NoPadding')` | 是 | 可直接替换 RN 端的 `rn-encryption` |
| HMAC-SHA512 | `cryptoFramework.createMac('SHA512')` | 是 | 替换 `expo-crypto` 自己拼的 HMAC |
| SHA-512 | `cryptoFramework.createMd('SHA512')` | 是 | |

**覆盖度评估**：Kit 能吃掉 AES-GCM / HMAC / SHA / 随机数 / PBKDF2 / X25519 协商这些通用原语；**但 NaCl 核心三件套（XSalsa20-Poly1305 secretbox、X25519+XSalsa20 box、Ed25519）没有可直接替代的 API**——前两个根本没有，Ed25519 待实机确认。这是必须自带代码的部分。

---

## 3. 方案对比

| 维度 | α 混合（Kit + TweetNaCl NAPI） | β 全量 libsodium NAPI | γ 纯 ArkTS 复写 | δ libsodium.js WASM |
|---|---|---|---|---|
| **代码量** | NAPI 薄层 ~300 行 + TweetNaCl C 700 行（或复用 SIG libsodium 二进制） | 复用 SIG 仓库（无新增 C 源码），NAPI 胶水 ~800 行覆盖全家桶 | ~1500 行 ArkTS（Curve25519+Salsa20+Poly1305+Ed25519） | 几乎零代码 |
| **工作量** | **1–2 人周**（含实机联调 + 跨端互操作测试） | 2–3 人周（CMake/ninja 适配 + ohpm 打包 + API 暴露面大） | 3–5 人周（加密代码自写风险高，需大量向量测试） | 0.5 人周（可行性未验证，见下行） |
| **可行性风险** | 低。TweetNaCl 是纯 C 700 行，无 autoconf 依赖，鸿蒙 NDK cmake 几分钟搞定；SIG libsodium 已通过官方 rk3568 构建 | 中。libsodium 原生 autoconf，OpenHarmony-SIG 已做过一次 port（[gitee.com/openharmony-sig/libsodium](https://gitee.com/openharmony-sig/libsodium) master 最后更新 2024-03），但 **不在 ohpm，需要自己做 NAPI 绑定和 HAR 打包** | 低（但工程量大） | **高风险**：ArkTS 运行时（ArkTS 1.2/方舟字节码）目前**没有公开文档证明支持 `WebAssembly.instantiate`**；社区仅提到 CocosRuntime 等第三方 runtime 支持 WASM，系统侧 ArkTS 环境中 WASM 可用性未确认 |
| **性能** | 原生 C，与 RN 端 libsodium 同档 | 同 α | 纯 TS/ArkTS，签名/公钥操作慢 5–20 倍（Ed25519 标量乘法在 TS 里基准约 20–50ms/次） | 若可用，接近原生 |
| **维护成本** | 低。NAPI 胶水层薄，TweetNaCl 几乎不更新 | 中。跟随 libsodium 上游升级需要重新交叉编译 | 高。自写加密代码长期审计负担重 | 若 WASM 可用则极低 |
| **与 happy-server/happy-agent 互通** | **字节级一致**（TweetNaCl 即 NaCl 规范实现，与 libsodium 的 `crypto_box/crypto_secretbox/crypto_sign` 输出完全一致） | 同 α（两者同标准） | 需要用 RFC/NaCl 测试向量严格比对 | 同 α |
| **上架合规（商密）风险** | 与 RN 版一致：使用境外开源加密库，App 上架需按《商用密码管理条例》如实声明；鸿蒙 AppGallery 侧对加密组件无额外白名单要求，与 Android 一致 | 同 α | 同 α | 同 α |
| **ArkTS 类型系统适配** | 仅 NAPI 边界 TS 声明文件，无痛 | 同 α | **需要重写**：纯 ArkTS 禁止结构化类型/运行时对象布局变更，npm 上的 tweetnacl-js 不能直接 `import`，必须人工移植（参见 [Porting Libraries to OpenHarmony](https://dl.acm.org/doi/10.1145/3728941)） | 如果能加载，JS 部分跑在兼容模式下 |

---

## 4. 推荐方案 + 下一步动作

### 推荐：方案 α

**鸿蒙端加密模块组成**：

1. **ArkTS 层（`encryption/` 模块）**：
   - `aes.ets` → `@ohos.security.cryptoFramework` AES-256-GCM
   - `hmac_sha512.ets` → `@ohos.security.cryptoFramework` HMAC-SHA512（替掉 happy-app 里手工拼的 HMAC）
   - `random.ets` → `cryptoFramework.createRandom()`
   - `deriveKey.ets` → 直接移植 `happy-agent/src/encryption.ts:49-72`（纯 TS，无外部依赖）
   - `libsodium.ets` → 薄包装，调用下层 NAPI 的 8 个入口
2. **NAPI 层（`native/nacl/` HAR 包）**：
   - 引入 TweetNaCl 的 `tweetnacl.c` + `tweetnacl.h`（700 行 C，ISC/MIT 许可）
   - `CMakeLists.txt` 用鸿蒙 NDK 编译
   - 导出 8 个入口：`box_keypair`、`box_seed_keypair`、`box_easy`、`box_open_easy`、`secretbox_easy`、`secretbox_open_easy`、`sign_seed_keypair`、`sign_detached`
   - 替代方案：直接复用 [OpenHarmony-SIG/libsodium](https://gitee.com/openharmony-sig/libsodium) 的预编译产物（功能更全，体积更大，约 300KB/arch）

### 下一步动作清单

1. **M1（0.5 人周）：可行性打桩**
   - 拉 `OpenHarmony-SIG/libsodium`，用 DevEco Studio + 鸿蒙 NDK 跑一次编译出 `.so`，确认工具链能产出 `arm64-v8a` 产物
   - 写最小 NAPI demo：`crypto_secretbox_easy` + `crypto_secretbox_open_easy` 跑通，输出和 Node 端 tweetnacl 字节级比对
2. **M2（1 人周）：完整 8 入口 NAPI + TS 声明**
   - 用 `happy-agent/src/encryption.ts` 作为测试 oracle：给出一组 seed/nonce/plaintext，两边跑对拍
   - 特别验证 `crypto_box_seed_keypair` 的 SHA-512[0:32] 语义（协议关键点）
3. **M3（0.5 人周）：AES-GCM / HMAC / 随机数走 Kit**
   - 拿 happy-agent 的 `encryptWithDataKey`/`decryptWithDataKey` 做 oracle（line 85-117），确保 nonce-12B + ciphertext + authTag-16B 布局一致
4. **M4（集成）**：在鸿蒙 app 中替换所有 `sodium.xxx` 调用，跑 E2E 连通性测试（与 happy-server prod 互通）

### 关于 Ed25519 的决策点

- 如果 M1 实机确认 `@ohos.security.cryptoFramework` 的 ArkTS API 支持 Ed25519 签名（关键字：`Ed25519`/`asymmetric.createAsyKeyGenerator('Ed25519')`），则可以把 `crypto_sign_*` 从 NAPI 层下掉，只走 Kit；TweetNaCl NAPI 只需保留 box/secretbox。
- 如果不支持，维持 NAPI 方案，成本几乎无差别（Ed25519 是 TweetNaCl 标配）。

### 风险点

1. **SIG libsodium 仓库最后更新 2024-03**，维护活跃度一般；长期建议自管镜像 + 跟踪上游 jedisct1/libsodium。如果方案 α 走 TweetNaCl 路线则无此风险。
2. **happy-harmony 端随机数**：不要用 `Math.random` 或 JS 侧伪随机；必须 `cryptoFramework.createRandom()`，否则 ephemeral keypair 和 nonce 不安全。
3. **字节级互操作**：所有"密钥派生 + ephemeral keypair + nonce 布局"细节见 `happy-agent/src/encryption.ts:74-81, 119-141, 182-205`，必须作为回归测试向量。

---

## 5. 参考资料

### happy 代码库（本地路径）

- `/Users/kchen/Workspace/remote-working/happy/packages/happy-app/sources/encryption/libsodium.ts` — RN 端 libsodium 全部调用点
- `/Users/kchen/Workspace/remote-working/happy/packages/happy-app/sources/encryption/libsodium.lib.ts` — 平台选择器（native = `@more-tech/react-native-libsodium`，web = `libsodium-wrappers`）
- `/Users/kchen/Workspace/remote-working/happy/packages/happy-app/sources/encryption/aes.ts` — AES-256-GCM via `rn-encryption`
- `/Users/kchen/Workspace/remote-working/happy/packages/happy-app/sources/encryption/hmac_sha512.ts` — HMAC 软实现
- `/Users/kchen/Workspace/remote-working/happy/packages/happy-app/sources/encryption/deriveKey.ts` — BIP32-like KDF
- `/Users/kchen/Workspace/remote-working/happy/packages/happy-app/sources/auth/authChallenge.ts` — Ed25519 签名
- `/Users/kchen/Workspace/remote-working/happy/packages/happy-app/sources/sync/encryption/encryption.ts` — 顶层协议编排
- `/Users/kchen/Workspace/remote-working/happy/packages/happy-app/sources/sync/encryption/encryptor.ts` — SecretBox / Box / AES256 实现
- `/Users/kchen/Workspace/remote-working/happy/packages/happy-agent/src/encryption.ts` — **纯 tweetnacl + node:crypto 的参考实现，是鸿蒙端对拍的 oracle**
- `/Users/kchen/Workspace/remote-working/happy/packages/happy-server/sources/app/api/routes/authRoutes.ts` — 服务端签名校验
- `/Users/kchen/Workspace/remote-working/happy/packages/happy-wire/src/` — 协议数据结构（无加密算法约束）

### 鸿蒙官方

- [Key Agreement Using X25519 (C/C++)](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/crypto-key-agreement-using-x25519-ndk)
- [cryptoFramework.createCipher](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-cryptoframework)
- [Asymmetric Key Generation and Conversion Specifications](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V13/crypto-asym-key-generation-conversion-spec-V13)
- [Signing and Signature Verification Development](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/crypto-sign-sig-verify-dev-V14)
- [Key Derivation Using PBKDF2](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/crypto-key-derivation-using-pbkdf2)
- [Crypto Architecture Kit Introduction](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/crypto-architecture-kit-intro-V5)
- [TypeScript to ArkTS Cookbook](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/typescript-to-arkts-migration-guide)

### OpenHarmony 生态

- [OpenHarmony-SIG/libsodium](https://gitee.com/openharmony-sig/libsodium) — C 级别 port，无 NAPI 绑定，无 ohpm 包，最后更新 2024-03，master 分支，1.0.0 tag
- [openharmony/ace_napi](https://github.com/openharmony/ace_napi) — NAPI 框架
- [ohos-rs/ohos-rs](https://github.com/ohos-rs/ohos-rs) — Rust NAPI 绑定（备选 NAPI 实现路径）
- [Node-API Part-1: Introduction](https://dev.to/harmonyos/node-api-part-1-introduction-to-node-api-wrapping-native-c-objects-in-arkts-on-harmonyosnext-13o0)
- [Porting Software Libraries to OpenHarmony (ISSTA 2025)](https://dl.acm.org/doi/10.1145/3728941) — 论证 ArkTS 不能直接吃 npm 包，需要移植
- [OHPM Introduction](https://docs.oniroproject.org/application-development/environment-setup-config/ohpm/)

### 上游加密库

- [jedisct1/libsodium](https://github.com/jedisct1/libsodium) — C 源码
- [jedisct1/libsodium.js](https://github.com/jedisct1/libsodium.js/) — WASM/pure JS 构建（δ 方案依赖）
- [TweetNaCl (tweetnacl.cr.yp.to)](https://tweetnacl.cr.yp.to/) — 100 tweet 可审计 C 实现
- [tweetnacl (npm)](https://www.npmjs.com/package/tweetnacl) — JS port（happy-agent/happy-server 当前使用）
- [github/tweetsodium](https://github.com/github/tweetsodium) — 仅 sealed box，不满足 happy 需求
