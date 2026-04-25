// Convenience facade over libnacl.so. Direct callers can also
// `import nacl from 'libnacl.so'` and get the same surface — the
// transitive dependency is exposed by this HAR. We keep this entry as
// a documented re-export point for future modules that prefer named
// imports.

export {
  KeyPair,
  secretboxEasy,
  secretboxOpenEasy,
  cryptoBoxKeypair,
  cryptoBoxKeypairFromSeed,
  cryptoBoxEasy,
  cryptoBoxOpenEasy,
  cryptoSignKeypairFromSeed,
  cryptoSignDetached,
  cryptoSignVerifyDetached,
} from 'libnacl.so';

export const SECRETBOX_KEY_BYTES = 32;
export const SECRETBOX_NONCE_BYTES = 24;
export const SECRETBOX_MAC_BYTES = 16;

export const BOX_PUBLIC_KEY_BYTES = 32;
export const BOX_SECRET_KEY_BYTES = 32;
export const BOX_NONCE_BYTES = 24;
export const BOX_MAC_BYTES = 16;
export const BOX_SEED_BYTES = 32;

export const SIGN_PUBLIC_KEY_BYTES = 32;
export const SIGN_SECRET_KEY_BYTES = 64;
export const SIGN_BYTES = 64;
export const SIGN_SEED_BYTES = 32;
