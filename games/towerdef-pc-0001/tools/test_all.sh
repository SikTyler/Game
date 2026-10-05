#!/usr/bin/env bash
# Corehold PC — the per-phase gate (V2_PROGRESS §Gates). Run from anywhere:
#   G=<godot mono binary> bash games/towerdef-pc-0001/tools/test_all.sh [--no-smoke]
# import -> C# build -> parse every script -> selftest -> uitest -> horde_fp x2
# (same hash) -> smoke playtest. Exit 1 on the first failing gate.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
G="${G:-$(bash "$HERE/tools/setup_godot.sh" --print)}"
OUT="${TEST_OUT:-${TMPDIR:-/tmp}/corehold-tests}"
mkdir -p "$OUT"
cd "$HERE"
fail() { echo "GATE FAIL: $1 (log: $OUT/$2)"; tail -25 "$OUT/$2"; exit 1; }
gate() { # name log grep-ok cmd...
  local name="$1" log="$2" ok="$3"; shift 3
  local t0=$SECONDS
  timeout 3000 "$@" > "$OUT/$log" 2>&1
  grep -q "$ok" "$OUT/$log" || fail "$name" "$log"
  if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$OUT/$log"; then fail "$name (script error)" "$log"; fi
  echo "GATE OK: $name ($((SECONDS - t0)) s)"
}
timeout 900 "$G" --headless --path . --import > "$OUT/import.log" 2>&1 || fail import import.log
timeout 900 "$G" --headless --path . --build-solutions --quit > "$OUT/build.log" 2>&1 || fail build build.log
if grep -qE "error CS[0-9]+" "$OUT/build.log"; then fail "C# build" build.log; fi
echo "GATE OK: import + C# build"
gate parse_all parse.log "PARSE OK" "$G" --headless --path . --script res://tools/parse_all.gd
gate selftest selftest.log "SELFTEST OK" "$G" --headless --path . --script res://selftest.gd
gate uitest uitest.log "UITEST OK" "$G" --headless --path . --script res://uitest.gd
gate horde_fp horde_fp1.log "HORDE FP ALL" "$G" --headless --path . --script res://horde_fp.gd
gate horde_fp_again horde_fp2.log "HORDE FP ALL" "$G" --headless --path . --script res://horde_fp.gd
h1="$(grep 'HORDE FP ALL' "$OUT/horde_fp1.log")"; h2="$(grep 'HORDE FP ALL' "$OUT/horde_fp2.log")"
[[ "$h1" == "$h2" ]] || { echo "GATE FAIL: horde_fp not deterministic: $h1 vs $h2"; exit 1; }
echo "GATE OK: horde_fp deterministic ($h1)"
if [[ "${1:-}" != "--no-smoke" ]]; then
  gate smoke smoke.log "SMOKE OK" "$G" --headless --path . --script res://smoke.gd
fi
echo "ALL GATES OK"
