#!/usr/bin/env bash
# Bootstrap debug signing for a fresh clone.
#
# Steps:
#   1. Symlink ./signing/material → ~/.ohos/config/material so hvigor's
#      DecipherUtil can find the AES-128-GCM master key it needs to
#      decrypt keyPassword/storePassword at SignHap time.
#   2. Copy ~/.ohos/config/default_<project>_*.{cer,p12,p7b} into
#      ./signing/<project>.{cer,p12,p7b} (relative paths in
#      build-profile.json5).
#   3. If build-profile.json5 has been overwritten by DevEco's GUI
#      "Signing Configs" wizard with literal hex blobs, lift them out
#      into .env.local and restore the ${env.…} placeholders.
#
# Idempotent — safe to re-run after rotating the cert.
#
# Usage:
#   scripts/setup-signing.sh                  # project name = happy-harmony
#   scripts/setup-signing.sh <other-project>
set -e
cd "$(dirname "$0")/.."
PROJ_NAME="${1:-happy-harmony}"

# 1. material/ symlink — required by hvigor's password decipher.
material_src="$HOME/.ohos/config/material"
if [ ! -d "$material_src" ]; then
  echo "✗ $material_src missing." >&2
  echo "  Open DevEco Studio at least once and let it auto-generate signing." >&2
  exit 1
fi
mkdir -p signing
ln -sfn "$material_src" signing/material
echo "✓ signing/material → $material_src"

# 2. cert / keystore / profile.
shopt -s nullglob
candidates=("$HOME/.ohos/config/default_${PROJ_NAME}_"*.cer)
shopt -u nullglob
if [ ${#candidates[@]} -eq 0 ]; then
  echo "✗ no signing material in $HOME/.ohos/config/default_${PROJ_NAME}_*.cer" >&2
  echo "  Generate via DevEco Build → Generate Key and CSR, accepting" >&2
  echo "  the auto-fill into build-profile.json5; then re-run this script." >&2
  exit 1
fi
# Pick the lexicographically last one (newest hash if multiple
# regenerations). bash 3 (the macOS default) doesn't allow negative
# subscripts, so go via printf|sort|tail.
src_cer=$(printf '%s\n' "${candidates[@]}" | sort | tail -n1)
prefix="${src_cer%.cer}"
for ext in cer p12 p7b; do
  src="${prefix}.${ext}"
  if [ ! -f "$src" ]; then
    echo "✗ expected $src" >&2
    exit 1
  fi
  cp "$src" "signing/${PROJ_NAME}.${ext}"
  echo "✓ signing/${PROJ_NAME}.${ext} ← $(basename "$src")"
done

# 3. Lift literal blobs out of build-profile.json5 if present.
keypw=$(grep -E '"keyPassword"' build-profile.json5 | head -1 \
         | sed -E 's/.*"keyPassword"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || true)
storepw=$(grep -E '"storePassword"' build-profile.json5 | head -1 \
           | sed -E 's/.*"storePassword"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || true)

case "$keypw$storepw" in
  *'${env.'*)
    echo "✓ build-profile.json5 already uses \${env.…} placeholders"
    if [ ! -f .env.local ]; then
      echo "  but .env.local is missing." >&2
      echo "  Use DevEco GUI → Project Structure → Signing Configs once to" >&2
      echo "  let it write literal blobs into build-profile.json5, then re-run" >&2
      echo "  this script to harvest them." >&2
      exit 1
    fi
    ;;
  *)
    if [ -z "$keypw" ] || [ -z "$storepw" ]; then
      echo "✗ couldn't read keyPassword/storePassword from build-profile.json5" >&2
      exit 1
    fi
    cat > .env.local <<EOF
# Local dev secrets — DO NOT COMMIT (gitignored).
# Sourced by scripts/build.sh before invoking hvigor; values are the
# DevEco-encrypted password blobs for the debug keystore at
# ./signing/${PROJ_NAME}.p12 and bound to that one keystore. Regenerate
# via DevEco Build → Generate Key and CSR + scripts/setup-signing.sh.
export HAPPY_HARMONY_KEY_PASSWORD='$keypw'
export HAPPY_HARMONY_STORE_PASSWORD='$storepw'
EOF
    chmod 600 .env.local
    echo "✓ harvested blobs into .env.local (mode 600)"

    python3 - "$keypw" "$storepw" <<'PY'
import sys
keypw, storepw = sys.argv[1], sys.argv[2]
src = open('build-profile.json5').read()
src = src.replace(f'"{keypw}"', '"${env.HAPPY_HARMONY_KEY_PASSWORD}"', 1)
src = src.replace(f'"{storepw}"', '"${env.HAPPY_HARMONY_STORE_PASSWORD}"', 1)
open('build-profile.json5', 'w').write(src)
PY
    echo "✓ build-profile.json5 restored to \${env.…} form"
    ;;
esac

echo ""
echo "Setup complete. Build with:"
echo "  scripts/build.sh assembleHap --mode module -p product=default -p buildMode=debug"
