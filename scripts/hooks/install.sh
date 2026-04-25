#!/usr/bin/env bash
# Symlink scripts/hooks/* into the repo's actual hooks directory.
# Resolves through gitfile/submodule indirection (this project is a
# submodule of the outer remote-working repo, so .git is a text file
# pointing at .git/modules/happy-harmony/).
set -e
cd "$(dirname "$0")/../.."
hooks_dir=$(git rev-parse --git-dir)/hooks
mkdir -p "$hooks_dir"
for f in scripts/hooks/*; do
  name=$(basename "$f")
  case "$name" in install.sh) continue;; esac
  abs=$(cd "$(dirname "$f")" && pwd)/$(basename "$f")
  ln -sf "$abs" "$hooks_dir/$name"
  chmod +x "$f"
  echo "linked $hooks_dir/$name -> $abs"
done
