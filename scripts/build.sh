#!/usr/bin/env bash
# Command-line wrapper for hvigorw.
#
# What this does:
#   1. Sources ./.env.local for the two debug-signing password blobs.
#   2. Renders ${env.HAPPY_HARMONY_KEY_PASSWORD} / _STORE_PASSWORD inside
#      build-profile.json5 to their actual values for the duration of
#      the build, restores the env-ref version on exit (success, fail,
#      Ctrl-C — anything except SIGKILL).
#   3. Invokes hvigorw with DevEco's bundled toolchain paths.
#
# Why we patch the file in place rather than via hvigorfile.ts:
#   hvigor's plugin API exposes setBuildProfileOpt and setOverrides, but
#   neither feeds SignHap (verified empirically: SignHap reads a
#   different cached profile that the plugin can't reach, and
#   setOverrides rejects non-dependency keys with code 00303184). So we
#   give hvigor what it wants by hand and undo it after the build.
#
#   Pre-commit hook (scripts/hooks/pre-commit) catches the case where the
#   patched version somehow makes it to git index. .gitignore excludes
#   the .envref backup.
#
# Examples:
#   scripts/build.sh assembleHap
#   scripts/build.sh assembleHap --mode module -p product=default -p buildMode=debug
set -e

cd "$(dirname "$0")/.."

if [ -f .env.local ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env.local
  set +a
fi

if [ -z "${HAPPY_HARMONY_KEY_PASSWORD:-}" ] || [ -z "${HAPPY_HARMONY_STORE_PASSWORD:-}" ]; then
  echo "scripts/build.sh: HAPPY_HARMONY_KEY_PASSWORD or HAPPY_HARMONY_STORE_PASSWORD missing" >&2
  echo "  add them to .env.local (gitignored) — see build-profile.json5 header for the format" >&2
  exit 1
fi

# Stale .envref from a previous SIGKILL'd run? Restore it before we touch
# the file again, otherwise we'd overwrite the source-of-truth env-ref
# version with whatever was patched last time.
if [ -f build-profile.json5.envref ]; then
  echo "scripts/build.sh: recovering build-profile.json5 from prior run" >&2
  cp build-profile.json5.envref build-profile.json5
  rm -f build-profile.json5.envref
fi

restore() {
  if [ -f build-profile.json5.envref ]; then
    cp build-profile.json5.envref build-profile.json5
    rm -f build-profile.json5.envref
  fi
}
trap restore EXIT INT TERM

cp build-profile.json5 build-profile.json5.envref
# Use a non-/ delimiter — the values are hex but escaping is cheaper this way.
python3 -c "
import os, re, sys
src = open('build-profile.json5').read()
src = src.replace('\${env.HAPPY_HARMONY_KEY_PASSWORD}', os.environ['HAPPY_HARMONY_KEY_PASSWORD'])
src = src.replace('\${env.HAPPY_HARMONY_STORE_PASSWORD}', os.environ['HAPPY_HARMONY_STORE_PASSWORD'])
open('build-profile.json5', 'w').write(src)
"

DEVECO=/Applications/DevEco-Studio.app/Contents
export DEVECO_SDK_HOME="$DEVECO/sdk"
export NODE_HOME="$DEVECO/tools/node"
export PATH="$NODE_HOME/bin:$PATH"

"$DEVECO/tools/hvigor/bin/hvigorw" "$@" --no-daemon
