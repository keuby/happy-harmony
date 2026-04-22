// libstage.so entry point.
//
// Exports:
//   add(a, b)                  — sanity check carried over from the
//                                Native C++ template.
//   secretboxEasy(m, n, k)     — XSalsa20-Poly1305 authenticated encryption
//                                (libsodium "easy" API).
//   secretboxOpenEasy(c, n, k) — counterpart; returns null on MAC failure.

#include "napi/native_api.h"

#include <cstdint>
#include <cstring>
#include <vector>

extern "C" {
#include "tweetnacl/tweetnacl.h"
}

namespace {

constexpr size_t kSecretboxKeyBytes = 32;
constexpr size_t kSecretboxNonceBytes = 24;
constexpr size_t kSecretboxZeroBytes = 32;
constexpr size_t kSecretboxBoxZeroBytes = 16;
constexpr size_t kSecretboxMacBytes =
    kSecretboxZeroBytes - kSecretboxBoxZeroBytes;

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
  napi_get_typedarray_info(env, val, &type, &length, &data, &arraybuffer,
                           &byte_offset);
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
  napi_create_typedarray(env, napi_uint8_array, len, arraybuffer, 0,
                         &typedarray);
  return typedarray;
}

napi_value Add(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  double a = 0, b = 0;
  napi_get_value_double(env, args[0], &a);
  napi_get_value_double(env, args[1], &b);
  napi_value sum;
  napi_create_double(env, a + b, &sum);
  return sum;
}

napi_value SecretboxEasy(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 3) {
    napi_throw_type_error(env, nullptr, "secretboxEasy requires 3 arguments");
    return nullptr;
  }

  const uint8_t *m = nullptr, *n = nullptr, *k = nullptr;
  size_t m_len = 0, n_len = 0, k_len = 0;
  if (!GetU8View(env, args[0], 0, 0, &m, &m_len)) return nullptr;
  if (!GetU8View(env, args[1], kSecretboxNonceBytes, 0, &n, &n_len)) return nullptr;
  if (!GetU8View(env, args[2], kSecretboxKeyBytes, 0, &k, &k_len)) return nullptr;

  // NaCl raw API requires the first 32 bytes of plaintext to be zero.
  const size_t padded_len = kSecretboxZeroBytes + m_len;
  std::vector<uint8_t> padded_m(padded_len, 0);
  if (m_len > 0) std::memcpy(padded_m.data() + kSecretboxZeroBytes, m, m_len);

  std::vector<uint8_t> padded_c(padded_len, 0);
  int rc = crypto_secretbox(padded_c.data(), padded_m.data(), padded_len, n, k);
  if (rc != 0) {
    napi_throw_error(env, nullptr, "crypto_secretbox failed");
    return nullptr;
  }

  // Output = [16 zero || MAC(16) || ct]; "easy" returns [MAC || ct].
  return MakeU8Array(env, padded_c.data() + kSecretboxBoxZeroBytes,
                     padded_len - kSecretboxBoxZeroBytes);
}

napi_value SecretboxOpenEasy(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 3) {
    napi_throw_type_error(env, nullptr, "secretboxOpenEasy requires 3 arguments");
    return nullptr;
  }

  const uint8_t *c = nullptr, *n = nullptr, *k = nullptr;
  size_t c_len = 0, n_len = 0, k_len = 0;
  if (!GetU8View(env, args[0], 0, kSecretboxMacBytes, &c, &c_len)) return nullptr;
  if (!GetU8View(env, args[1], kSecretboxNonceBytes, 0, &n, &n_len)) return nullptr;
  if (!GetU8View(env, args[2], kSecretboxKeyBytes, 0, &k, &k_len)) return nullptr;

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

  return MakeU8Array(env, padded_m.data() + kSecretboxZeroBytes,
                     padded_len - kSecretboxZeroBytes);
}

}  // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"secretboxEasy", nullptr, SecretboxEasy, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"secretboxOpenEasy", nullptr, SecretboxOpenEasy, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  return exports;
}
EXTERN_C_END

static napi_module stageModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "stage",
    .nm_priv = ((void*)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterStageModule(void) {
  napi_module_register(&stageModule);
}
