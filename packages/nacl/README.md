# @ohos/nacl — TweetNaCl NAPI module for HarmonyOS Next

Pure-ArkTS port of the NaCl subset that `slopus/happy` actually uses.
PoC-A2 scope: `crypto_secretbox_easy` / `crypto_secretbox_open_easy`
(XSalsa20-Poly1305). `crypto_box_*` and `crypto_sign_*` land in a later
iteration once this round is green on device.

## Sources

- `src/cpp/tweetnacl/tweetnacl.{c,h}` — TweetNaCl 20140427, Bernstein et al,
  public domain. Unmodified from `https://tweetnacl.cr.yp.to/20140427/`.
- `src/cpp/tweetnacl/randombytes.c` — reads `/dev/urandom`. Only referenced
  by `crypto_box_keypair` / `crypto_sign_keypair`, not by `secretbox`.
- `src/cpp/napi/nacl_napi.cpp` — NAPI bindings. Implements the libsodium
  "easy" API layout (`[16-byte MAC || ciphertext]`) on top of TweetNaCl's
  raw NaCl API (`[16 zero bytes || 16-byte MAC || ciphertext]`).

## Build

### Standalone smoke test (CLI, no DevEco)

Sanity-checks that the OpenHarmony NDK toolchain produces a loadable
`libnacl.z.so` for `aarch64-linux-ohos`.

```sh
./smoke-test.sh
```

Defaults to the NDK bundled with DevEco Studio at
`/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native`.
Override with `OHOS_SDK=... ./smoke-test.sh`.

### Inside a DevEco project (CMake)

`src/cpp/CMakeLists.txt` is Hvigor-friendly. In a DevEco project, copy or
symlink `src/cpp/` under `entry/src/main/cpp/` (or into a dedicated HAR's
`src/main/cpp/`), and DevEco's Hvigor will pick up the CMake config.

## ArkTS surface

```typescript
import { secretboxEasy, secretboxOpenEasy } from '@ohos/nacl';

const ct = secretboxEasy(plaintext, nonce /* 24 */, key /* 32 */);
const pt = secretboxOpenEasy(ct, nonce, key);   // null on auth failure
```

## Correctness testing

Byte-level agreement with `tweetnacl-js` (the reference implementation
used by `happy-agent` and `happy-server`) is verified via fixtures in
`../../tests/vectors/secretbox.json`, regenerated with
`tests/vectors/generate.mjs`. Drop `tests/vectors/runner.ets` into a
HarmonyOS app to run them on device.

## Status

| Stage | Where | Status |
|---|---|---|
| NDK compiles `tweetnacl.c` | `smoke-test.sh` step 1 | ✅ |
| NAPI cpp compiles | `smoke-test.sh` step 3 | ✅ |
| `libnacl.z.so` links cleanly | `smoke-test.sh` step 4 | ✅ |
| On-device load + runtime call | Needs DevEco HAP | ⏳ |
| Byte-equivalence with tweetnacl-js | `runner.ets` on device | ⏳ |
