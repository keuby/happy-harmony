// libstage.so entry point.
//
// Same NAPI surface as packages/nacl (see napi/nacl_napi.cpp in that package
// for design notes). Kept in sync by hand; an `add()` sanity export remains
// from the Native C++ template for smoke-checking NAPI registration on device.

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

constexpr size_t kBoxPublicKeyBytes = 32;
constexpr size_t kBoxSecretKeyBytes = 32;
constexpr size_t kBoxNonceBytes = 24;
constexpr size_t kBoxZeroBytes = 32;
constexpr size_t kBoxBoxZeroBytes = 16;
constexpr size_t kBoxMacBytes = kBoxZeroBytes - kBoxBoxZeroBytes;
constexpr size_t kBoxSeedBytes = 32;

constexpr size_t kSignPublicKeyBytes = 32;
constexpr size_t kSignSecretKeyBytes = 64;
constexpr size_t kSignBytes = 64;
constexpr size_t kSignSeedBytes = 32;

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

napi_value MakeKeyPair(napi_env env, const uint8_t* pk, size_t pk_len,
                      const uint8_t* sk, size_t sk_len) {
  napi_value obj;
  napi_create_object(env, &obj);
  napi_set_named_property(env, obj, "publicKey", MakeU8Array(env, pk, pk_len));
  napi_set_named_property(env, obj, "secretKey", MakeU8Array(env, sk, sk_len));
  return obj;
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

  const size_t padded_len = kSecretboxZeroBytes + m_len;
  std::vector<uint8_t> padded_m(padded_len, 0);
  if (m_len > 0) std::memcpy(padded_m.data() + kSecretboxZeroBytes, m, m_len);

  std::vector<uint8_t> padded_c(padded_len, 0);
  int rc = crypto_secretbox(padded_c.data(), padded_m.data(), padded_len, n, k);
  if (rc != 0) {
    napi_throw_error(env, nullptr, "crypto_secretbox failed");
    return nullptr;
  }

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

napi_value CryptoBoxKeypair(napi_env env, napi_callback_info info) {
  (void)info;
  uint8_t pk[kBoxPublicKeyBytes];
  uint8_t sk[kBoxSecretKeyBytes];
  int rc = crypto_box_keypair(pk, sk);
  if (rc != 0) {
    napi_throw_error(env, nullptr, "crypto_box_keypair failed");
    return nullptr;
  }
  return MakeKeyPair(env, pk, sizeof(pk), sk, sizeof(sk));
}

napi_value CryptoBoxKeypairFromSeed(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 1) {
    napi_throw_type_error(env, nullptr, "cryptoBoxKeypairFromSeed requires 1 argument");
    return nullptr;
  }

  const uint8_t* seed = nullptr;
  size_t seed_len = 0;
  if (!GetU8View(env, args[0], kBoxSeedBytes, 0, &seed, &seed_len)) return nullptr;

  // libsodium's crypto_box_seed_keypair: sk = SHA-512(seed)[0..32],
  // pk = scalarmult_base(sk). Must match this exactly — happy-server's
  // session.dataEncryptionKey is boxed against the libsodium-derived
  // public key, and happy-app's sodium.crypto_box_seed_keypair goes
  // through the same hash. A bare memcpy(sk, seed) here would derive
  // a different keypair and every cross-app box would mismatch.
  uint8_t h[64];
  crypto_hash_sha512(h, seed, kBoxSeedBytes);
  uint8_t sk[kBoxSecretKeyBytes];
  uint8_t pk[kBoxPublicKeyBytes];
  std::memcpy(sk, h, kBoxSecretKeyBytes);
  int rc = crypto_scalarmult_base(pk, sk);
  if (rc != 0) {
    napi_throw_error(env, nullptr, "crypto_scalarmult_base failed");
    return nullptr;
  }
  return MakeKeyPair(env, pk, sizeof(pk), sk, sizeof(sk));
}

napi_value CryptoBoxEasy(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 4) {
    napi_throw_type_error(env, nullptr, "cryptoBoxEasy requires 4 arguments");
    return nullptr;
  }

  const uint8_t *m = nullptr, *n = nullptr, *pk = nullptr, *sk = nullptr;
  size_t m_len = 0, n_len = 0, pk_len = 0, sk_len = 0;
  if (!GetU8View(env, args[0], 0, 0, &m, &m_len)) return nullptr;
  if (!GetU8View(env, args[1], kBoxNonceBytes, 0, &n, &n_len)) return nullptr;
  if (!GetU8View(env, args[2], kBoxPublicKeyBytes, 0, &pk, &pk_len)) return nullptr;
  if (!GetU8View(env, args[3], kBoxSecretKeyBytes, 0, &sk, &sk_len)) return nullptr;

  const size_t padded_len = kBoxZeroBytes + m_len;
  std::vector<uint8_t> padded_m(padded_len, 0);
  if (m_len > 0) std::memcpy(padded_m.data() + kBoxZeroBytes, m, m_len);

  std::vector<uint8_t> padded_c(padded_len, 0);
  int rc = crypto_box(padded_c.data(), padded_m.data(), padded_len, n, pk, sk);
  if (rc != 0) {
    napi_throw_error(env, nullptr, "crypto_box failed");
    return nullptr;
  }

  return MakeU8Array(env, padded_c.data() + kBoxBoxZeroBytes,
                     padded_len - kBoxBoxZeroBytes);
}

napi_value CryptoBoxOpenEasy(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 4) {
    napi_throw_type_error(env, nullptr, "cryptoBoxOpenEasy requires 4 arguments");
    return nullptr;
  }

  const uint8_t *c = nullptr, *n = nullptr, *pk = nullptr, *sk = nullptr;
  size_t c_len = 0, n_len = 0, pk_len = 0, sk_len = 0;
  if (!GetU8View(env, args[0], 0, kBoxMacBytes, &c, &c_len)) return nullptr;
  if (!GetU8View(env, args[1], kBoxNonceBytes, 0, &n, &n_len)) return nullptr;
  if (!GetU8View(env, args[2], kBoxPublicKeyBytes, 0, &pk, &pk_len)) return nullptr;
  if (!GetU8View(env, args[3], kBoxSecretKeyBytes, 0, &sk, &sk_len)) return nullptr;

  const size_t padded_len = kBoxBoxZeroBytes + c_len;
  std::vector<uint8_t> padded_c(padded_len, 0);
  std::memcpy(padded_c.data() + kBoxBoxZeroBytes, c, c_len);

  std::vector<uint8_t> padded_m(padded_len, 0);
  int rc = crypto_box_open(padded_m.data(), padded_c.data(), padded_len, n, pk, sk);
  if (rc != 0) {
    napi_value null_val;
    napi_get_null(env, &null_val);
    return null_val;
  }

  return MakeU8Array(env, padded_m.data() + kBoxZeroBytes,
                     padded_len - kBoxZeroBytes);
}

napi_value CryptoSignKeypairFromSeed(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 1) {
    napi_throw_type_error(env, nullptr, "cryptoSignKeypairFromSeed requires 1 argument");
    return nullptr;
  }

  const uint8_t* seed = nullptr;
  size_t seed_len = 0;
  if (!GetU8View(env, args[0], kSignSeedBytes, 0, &seed, &seed_len)) return nullptr;

  uint8_t pk[kSignPublicKeyBytes];
  uint8_t sk[kSignSecretKeyBytes];
  int rc = crypto_sign_keypair_from_seed(pk, sk, seed);
  if (rc != 0) {
    napi_throw_error(env, nullptr, "crypto_sign_keypair_from_seed failed");
    return nullptr;
  }
  return MakeKeyPair(env, pk, sizeof(pk), sk, sizeof(sk));
}

napi_value CryptoSignDetached(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 2) {
    napi_throw_type_error(env, nullptr, "cryptoSignDetached requires 2 arguments");
    return nullptr;
  }

  const uint8_t* m = nullptr;
  size_t m_len = 0;
  const uint8_t* sk = nullptr;
  size_t sk_len = 0;
  if (!GetU8View(env, args[0], 0, 0, &m, &m_len)) return nullptr;
  if (!GetU8View(env, args[1], kSignSecretKeyBytes, 0, &sk, &sk_len)) return nullptr;

  const size_t sm_cap = kSignBytes + m_len;
  std::vector<uint8_t> sm(sm_cap, 0);
  unsigned long long sm_len = 0;
  int rc = crypto_sign(sm.data(), &sm_len, m, static_cast<unsigned long long>(m_len), sk);
  if (rc != 0 || sm_len < kSignBytes) {
    napi_throw_error(env, nullptr, "crypto_sign failed");
    return nullptr;
  }
  return MakeU8Array(env, sm.data(), kSignBytes);
}

napi_value CryptoSignVerifyDetached(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 3) {
    napi_throw_type_error(env, nullptr, "cryptoSignVerifyDetached requires 3 arguments");
    return nullptr;
  }

  const uint8_t* sig = nullptr;
  size_t sig_len = 0;
  const uint8_t* m = nullptr;
  size_t m_len = 0;
  const uint8_t* pk = nullptr;
  size_t pk_len = 0;
  if (!GetU8View(env, args[0], kSignBytes, 0, &sig, &sig_len)) return nullptr;
  if (!GetU8View(env, args[1], 0, 0, &m, &m_len)) return nullptr;
  if (!GetU8View(env, args[2], kSignPublicKeyBytes, 0, &pk, &pk_len)) return nullptr;

  const size_t sm_len = kSignBytes + m_len;
  std::vector<uint8_t> sm(sm_len);
  std::memcpy(sm.data(), sig, kSignBytes);
  if (m_len > 0) std::memcpy(sm.data() + kSignBytes, m, m_len);

  std::vector<uint8_t> out(sm_len);
  unsigned long long out_len = 0;
  int rc = crypto_sign_open(out.data(), &out_len, sm.data(),
                            static_cast<unsigned long long>(sm_len), pk);
  napi_value result;
  napi_get_boolean(env, rc == 0, &result);
  return result;
}

}  // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"secretboxEasy", nullptr, SecretboxEasy, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"secretboxOpenEasy", nullptr, SecretboxOpenEasy, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"cryptoBoxKeypair", nullptr, CryptoBoxKeypair, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"cryptoBoxKeypairFromSeed", nullptr, CryptoBoxKeypairFromSeed, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"cryptoBoxEasy", nullptr, CryptoBoxEasy, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"cryptoBoxOpenEasy", nullptr, CryptoBoxOpenEasy, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"cryptoSignKeypairFromSeed", nullptr, CryptoSignKeypairFromSeed, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"cryptoSignDetached", nullptr, CryptoSignDetached, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"cryptoSignVerifyDetached", nullptr, CryptoSignVerifyDetached, nullptr, nullptr, nullptr, napi_default, nullptr},
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
