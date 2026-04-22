// NAPI bindings for TweetNaCl.
// PoC-A2 scope: only crypto_secretbox_easy / crypto_secretbox_open_easy.
// crypto_box / crypto_sign bindings land in M2 once this round is green.

#include <napi/native_api.h>
#include <cstdint>
#include <cstring>
#include <vector>

extern "C" {
#include "tweetnacl.h"
}

namespace {

constexpr size_t kSecretboxKeyBytes = 32;
constexpr size_t kSecretboxNonceBytes = 24;
constexpr size_t kSecretboxZeroBytes = 32;    // NaCl pre-pad for plaintext
constexpr size_t kSecretboxBoxZeroBytes = 16; // NaCl pre-pad for ciphertext
constexpr size_t kSecretboxMacBytes =
    kSecretboxZeroBytes - kSecretboxBoxZeroBytes; // 16

// Extract a read-only view of a Uint8Array argument. Returns false and
// leaves an exception pending if the arg isn't a typed array of the
// exact required length (or at least min_len if exact_len == 0).
bool GetU8View(napi_env env, napi_value val, size_t exact_len, size_t min_len,
               const uint8_t** out_data, size_t* out_len) {
  bool is_typed = false;
  napi_is_typedarray(env, val, &is_typed);
  if (!is_typed) {
    napi_throw_type_error(env, nullptr, "argument must be a Uint8Array");
    return false;
  }
  napi_typedarray_type type;
  size_t length = 0;
  void* data = nullptr;
  napi_value arraybuffer;
  size_t byte_offset = 0;
  napi_get_typedarray_info(env, val, &type, &length, &data, &arraybuffer, &byte_offset);
  if (type != napi_uint8_array) {
    napi_throw_type_error(env, nullptr, "argument must be a Uint8Array");
    return false;
  }
  if (exact_len > 0 && length != exact_len) {
    napi_throw_range_error(env, nullptr, "argument has wrong byte length");
    return false;
  }
  if (min_len > 0 && length < min_len) {
    napi_throw_range_error(env, nullptr, "argument is shorter than required");
    return false;
  }
  *out_data = static_cast<const uint8_t*>(data);
  *out_len = length;
  return true;
}

napi_value MakeU8Array(napi_env env, const uint8_t* data, size_t len) {
  napi_value arraybuffer;
  void* ab_data = nullptr;
  napi_create_arraybuffer(env, len, &ab_data, &arraybuffer);
  if (len > 0 && data != nullptr) std::memcpy(ab_data, data, len);
  napi_value typedarray;
  napi_create_typedarray(env, napi_uint8_array, len, arraybuffer, 0, &typedarray);
  return typedarray;
}

// secretboxEasy(message: Uint8Array, nonce: Uint8Array(24), key: Uint8Array(32)) -> Uint8Array
napi_value SecretboxEasy(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 3) {
    napi_throw_type_error(env, nullptr, "secretboxEasy requires 3 arguments");
    return nullptr;
  }

  const uint8_t* m = nullptr;
  size_t m_len = 0;
  const uint8_t* n = nullptr;
  size_t n_len = 0;
  const uint8_t* k = nullptr;
  size_t k_len = 0;
  if (!GetU8View(env, args[0], 0, 0, &m, &m_len)) return nullptr;
  if (!GetU8View(env, args[1], kSecretboxNonceBytes, 0, &n, &n_len)) return nullptr;
  if (!GetU8View(env, args[2], kSecretboxKeyBytes, 0, &k, &k_len)) return nullptr;

  // NaCl's raw API requires the first 32 bytes of the plaintext buffer to
  // be zero. Build padded_m = [32 zero bytes || message].
  const size_t padded_len = kSecretboxZeroBytes + m_len;
  std::vector<uint8_t> padded_m(padded_len, 0);
  if (m_len > 0) std::memcpy(padded_m.data() + kSecretboxZeroBytes, m, m_len);

  std::vector<uint8_t> padded_c(padded_len, 0);
  int rc = crypto_secretbox(padded_c.data(), padded_m.data(), padded_len, n, k);
  if (rc != 0) {
    napi_throw_error(env, nullptr, "crypto_secretbox failed");
    return nullptr;
  }

  // Output is [16 zero bytes || 16-byte MAC || ciphertext]; the "easy" API
  // returns [MAC || ciphertext].
  return MakeU8Array(env, padded_c.data() + kSecretboxBoxZeroBytes,
                     padded_len - kSecretboxBoxZeroBytes);
}

// secretboxOpenEasy(ciphertext: Uint8Array(>=16), nonce: Uint8Array(24),
//   key: Uint8Array(32)) -> Uint8Array | null
napi_value SecretboxOpenEasy(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 3) {
    napi_throw_type_error(env, nullptr, "secretboxOpenEasy requires 3 arguments");
    return nullptr;
  }

  const uint8_t* c = nullptr;
  size_t c_len = 0;
  const uint8_t* n = nullptr;
  size_t n_len = 0;
  const uint8_t* k = nullptr;
  size_t k_len = 0;
  if (!GetU8View(env, args[0], 0, kSecretboxMacBytes, &c, &c_len)) return nullptr;
  if (!GetU8View(env, args[1], kSecretboxNonceBytes, 0, &n, &n_len)) return nullptr;
  if (!GetU8View(env, args[2], kSecretboxKeyBytes, 0, &k, &k_len)) return nullptr;

  // Raw API wants [16 zero bytes || MAC || ciphertext]; easy API gives
  // [MAC || ciphertext].
  const size_t padded_len = kSecretboxBoxZeroBytes + c_len;
  std::vector<uint8_t> padded_c(padded_len, 0);
  std::memcpy(padded_c.data() + kSecretboxBoxZeroBytes, c, c_len);

  std::vector<uint8_t> padded_m(padded_len, 0);
  int rc = crypto_secretbox_open(padded_m.data(), padded_c.data(), padded_len, n, k);
  if (rc != 0) {
    napi_value null_val;
    napi_get_null(env, &null_val);
    return null_val;
  }

  // Output is [32 zero bytes || plaintext].
  return MakeU8Array(env, padded_m.data() + kSecretboxZeroBytes,
                     padded_len - kSecretboxZeroBytes);
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"secretboxEasy", nullptr, SecretboxEasy, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"secretboxOpenEasy", nullptr, SecretboxOpenEasy, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  return exports;
}

}  // namespace

extern "C" {

static napi_module nacl_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "nacl",
    .nm_priv = nullptr,
    .reserved = {0},
};

__attribute__((constructor)) void RegisterNaclModule(void) {
  napi_module_register(&nacl_module);
}

}  // extern "C"
