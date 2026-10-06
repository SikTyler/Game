// GPU-free procedural music for GameForge: renders a ZzFXM song (vendored unmodified under
// tools/vendor/zzfxm/, MIT) to a deterministic 16-bit stereo 44.1 kHz WAV whose length is
// EXACTLY the song's sequence length; any release tail past the end is wrapped (mixed) back
// onto the start, so the file loops seamlessly with Godot's loop_mode = forward.
//
// CLI: node tools/music.mjs render <id> <name> <song.json>  -> games/<id>/audio/<name>.wav
// song.json: {"instruments":[[...zzfx]], "patterns":[[[inst,pan,note,...],...]], "sequence":[0,1], "bpm":120, "seed":1}
//   or the raw ZzFXM array form [instruments, patterns, sequence, bpm]. JSON nulls stand in
//   for ZzFXM's sparse-array holes. A .js file holding a bare ZzFXM array literal (like the
//   upstream examples/songs/*.js) is also accepted.

import vm from "node:vm";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join, resolve } from "node:path";
import { encodeWav } from "./wav.mjs";
import { loadZzfx, holesToUndefined, audioDir, SAMPLE_RATE } from "./sfx.mjs";

export function normalizeSong(song) {
  if (Array.isArray(song)) {
    const [instruments, patterns, sequence, bpm] = song;
    return { instruments, patterns, sequence, bpm: bpm ?? 125, seed: 1 };
  }
  const { instruments, patterns, sequence } = song;
  return { instruments, patterns, sequence, bpm: song.bpm ?? 125, seed: song.seed ?? 1, volume: song.volume };
}

/** Samples per beat-row exactly as zzfxm.js computes it. */
export function rowSamples(bpm) {
  return (SAMPLE_RATE / bpm * 60) >> 2;
}

/** Loop length in samples: every sequenced pattern's row count x row length. */
export function loopLength(song) {
  const s = normalizeSong(song);
  const rows = s.sequence.reduce((n, p) => n + (s.patterns[p][0].length - 2), 0);
  return rows * rowSamples(s.bpm);
}

export function renderSong(song) {
  const s = normalizeSong(song);
  if (!Array.isArray(s.instruments) || !Array.isArray(s.patterns) || !Array.isArray(s.sequence) || s.sequence.length === 0)
    throw new Error("song needs instruments, patterns and a non-empty sequence");
  const { ctx, math } = loadZzfx();
  math.reseed(s.seed);
  ctx.zzfxR = SAMPLE_RATE;
  ctx.zzfxV = typeof s.volume === "number" ? s.volume : 0.3;
  const [L, R] = ctx.zzfxM(holesToUndefined(s.instruments), holesToUndefined(s.patterns), s.sequence, s.bpm);
  const n = loopLength(s);
  const left = new Float64Array(n), right = new Float64Array(n);
  for (let i = 0; i < L.length; i++) {
    left[i % n] += L[i] || 0;
    right[i % n] += R[i] || 0;
  }
  return { left, right, frames: n, seconds: n / SAMPLE_RATE };
}

export function songWav(song) {
  const r = renderSong(song);
  return encodeWav([r.left, r.right], SAMPLE_RATE);
}

export function parseSongFile(text) {
  try { return JSON.parse(text); } catch { /* fall through: JS array literal */ }
  return vm.runInNewContext(`(${text.trim().replace(/;\s*$/, "")})`, {}, { timeout: 2000 });
}

export function renderToGame(id, name, song, root) {
  if (!/^[A-Za-z0-9_-]+$/.test(name)) throw new Error(`bad clip name "${name}"`);
  const dir = audioDir(id, root);
  mkdirSync(dir, { recursive: true });
  const out = join(dir, `${name}.wav`);
  const r = renderSong(song);
  writeFileSync(out, encodeWav([r.left, r.right], SAMPLE_RATE));
  return { out, seconds: r.seconds };
}

function main(argv) {
  const [cmd, id, name, file] = argv;
  if (cmd === "render" && file) {
    const r = renderToGame(id, name, parseSongFile(readFileSync(file, "utf8")));
    console.log(`wrote ${r.out} (${r.seconds.toFixed(3)} s, loop-exact)`);
    return 0;
  }
  console.error("usage: node tools/music.mjs render <id> <name> <song.json>");
  return 2;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exit(main(process.argv.slice(2)));
}
