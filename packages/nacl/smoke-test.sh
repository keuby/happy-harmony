#!/usr/bin/env bash
# Toolchain smoke test for PoC-A2.
# Compiles tweetnacl.c + randombytes.c with the OpenHarmony NDK clang to
# verify that the cross-compiler, sysroot, and source all play together.
# This produces a .so targeting aarch64-linux-ohos — it does NOT run on
# macOS. Successful compilation is the pass criterion; device execution
# is covered later by the HAR + test app.

set -euo pipefail

SDK="${OHOS_SDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"
CLANG="$SDK/llvm/bin/aarch64-unknown-linux-ohos-clang"
CLANGXX="$SDK/llvm/bin/aarch64-unknown-linux-ohos-clang++"
SYSROOT="$SDK/sysroot"
LIBDIR="$SYSROOT/usr/lib/aarch64-linux-ohos"

[[ -x "$CLANG" ]] || { echo "clang not found: $CLANG"; exit 1; }
[[ -d "$SYSROOT" ]] || { echo "sysroot not found: $SYSROOT"; exit 1; }

SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd)"
CPP_DIR="$SCRIPT_DIR/src/cpp"
BUILD_DIR="$SCRIPT_DIR/build/smoke"
mkdir -p "$BUILD_DIR"

C_FLAGS=(
  --target=aarch64-linux-ohos
  --sysroot="$SYSROOT"
  -O2
  -fPIC
  -Wall
  -Wextra
  -fvisibility=hidden
  -Wno-sign-compare
)

CXX_FLAGS=(
  "${C_FLAGS[@]}"
  -std=c++17
  -I"$CPP_DIR"
  -I"$CPP_DIR/tweetnacl"
)

echo "[1/4] Compiling tweetnacl.c ..."
"$CLANG" "${C_FLAGS[@]}" -c "$CPP_DIR/tweetnacl/tweetnacl.c" -o "$BUILD_DIR/tweetnacl.o"

echo "[2/4] Compiling randombytes.c ..."
"$CLANG" "${C_FLAGS[@]}" -c "$CPP_DIR/tweetnacl/randombytes.c" -o "$BUILD_DIR/randombytes.o"

echo "[3/4] Compiling nacl_napi.cpp ..."
"$CLANGXX" "${CXX_FLAGS[@]}" -c "$CPP_DIR/napi/nacl_napi.cpp" -o "$BUILD_DIR/nacl_napi.o"

echo "[4/4] Linking libnacl.z.so ..."
"$CLANGXX" --target=aarch64-linux-ohos --sysroot="$SYSROOT" -shared \
  -L"$LIBDIR" \
  "$BUILD_DIR/tweetnacl.o" "$BUILD_DIR/randombytes.o" "$BUILD_DIR/nacl_napi.o" \
  -lace_napi.z \
  -o "$BUILD_DIR/libnacl.z.so"

echo
file "$BUILD_DIR/libnacl.z.so" 2>/dev/null || stat "$BUILD_DIR/libnacl.z.so"
SIZE=$(wc -c < "$BUILD_DIR/libnacl.z.so")
echo "Size: $SIZE bytes"

echo
echo "=== NAPI module constructor ==="
"$SDK/llvm/bin/llvm-nm" -D --defined-only "$BUILD_DIR/libnacl.z.so" 2>/dev/null | grep -E "(RegisterNaclModule|napi_module_register)" || echo "(not in dynamic symbols — check static)"
"$SDK/llvm/bin/llvm-nm" --defined-only "$BUILD_DIR/libnacl.z.so" 2>/dev/null | grep -E "RegisterNaclModule"

echo
echo "=== Undefined symbols (must not contain crypto_* or random-y things) ==="
"$SDK/llvm/bin/llvm-nm" -D --undefined-only "$BUILD_DIR/libnacl.z.so" 2>/dev/null | grep -iE "(crypto_|random)" || echo "(clean — no unresolved crypto/random symbols)"

echo
echo "OK — NAPI module built successfully."
