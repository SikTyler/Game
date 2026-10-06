#!/usr/bin/env bash
# Corehold PC — idempotent headless toolchain for the test gates (V2_PROGRESS §Toolchain).
# Installs Godot 4.6.3 *mono* (the horde sim is C#) under ~/godot and the .NET 8
# SDK. Prints the Godot binary path; export it as G for tools/test_all.sh.
#   bash tools/setup_godot.sh && export G=$(bash tools/setup_godot.sh --print)
set -euo pipefail
GV="4.6.3"
DIR="$HOME/godot"
NAME="Godot_v${GV}-stable_mono_linux_x86_64"
BIN="$DIR/$NAME/Godot_v${GV}-stable_mono_linux.x86_64"
if [[ "${1:-}" == "--print" ]]; then echo "$BIN"; exit 0; fi
export SSL_CERT_FILE="${SSL_CERT_FILE:-/root/.ccr/ca-bundle.crt}"
mkdir -p "$DIR"
if [[ ! -x "$BIN" ]]; then
  curl -sSL -o "$DIR/g.zip" "https://github.com/godotengine/godot/releases/download/${GV}-stable/${NAME}.zip"
  (cd "$DIR" && unzip -q -o g.zip && rm -f g.zip)
fi
if ! command -v dotnet >/dev/null 2>&1; then
  # The Microsoft CDN may be blocked by an egress policy; the distro archive
  # ships the same SDK (Ubuntu 24.04: dotnet-sdk-8.0).
  if command -v apt-get >/dev/null 2>&1; then
    apt-get install -y dotnet-sdk-8.0 >/dev/null 2>&1 || (apt-get update >/dev/null 2>&1 && apt-get install -y dotnet-sdk-8.0 >/dev/null)
  else
    curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 8.0 --install-dir "$HOME/.dotnet"
  fi
fi
echo "$BIN"
