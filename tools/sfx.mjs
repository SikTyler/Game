// GPU-free procedural SFX for GameForge: renders jsfxr (sfxr) presets/params or ZzFX
// parameter arrays to deterministic 16-bit mono 44.1 kHz WAVs. The upstream synths are
// vendored UNMODIFIED under tools/vendor/ (jsfxr: Unlicense; ZzFX/ZzFXM: MIT) and run in a
// node:vm sandbox whose Math.random is a seeded PRNG, so the same recipe => identical bytes.
//
// CLI (from repo root):
//   node tools/sfx.mjs gen <id> <name> '<json>'      -> games/<id>/audio/<name>.wav
//   node tools/sfx.mjs gen-batch <id> <recipes.json> -> one WAV per sfx recipe
//   node tools/sfx.mjs presets                         -> list jsfxr preset names
//
// Recipe JSON (one of):
//   {"preset":"laserShoot","seed":7, "overrides":{"p_base_freq":0.4}, "volume":0.25}
//   {"zzfx":[1,.05,220,0,0,.1], "seed":3}
//   {"sfxr":{"wave_type":0,"p_env_sustain":0.2,...}}    (full sfxr params; same keys as jsfxr)
// recipes.json: {"recipes":[{"name":"shoot","kind":"sfx","synth":{...recipe...}}, ...]}
// (entries with kind:"music" are skipped here — see tools/music.mjs).

import vm from "node:vm";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";
import { encodeWav, seededMath } from "./wav.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = resolve(HERE, "..");
export const SAMPLE_RATE = 44100;

export const PRESETS = [
  "pickupCoin", "laserShoot", "explosion", "powerUp", "hitHurt",
  "jump", "blipSelect", "synth", "tone", "click", "random",
];

let _jsfxr = null;
function loadJsfxr() {
  if (_jsfxr) return _jsfxr;
  const math = seededMath();
  const src = readFileSync(join(HERE, "vendor/jsfxr/sfxr.js"), "utf8");
  // RIFFWAVE is only used by SoundEffect.generate() (browser <audio> path); we encode WAVs
  // ourselves from getRawBuffer().normalized, so a stub suffices.
  const sandbox = { Math, module: { exports: {} }, require: () => function RIFFWAVE() {}, console };
  sandbox.Math = math;
  vm.createContext(sandbox);
  vm.runInContext(src, sandbox, { filename: "sfxr.js" });
  _jsfxr = { lib: sandbox.module.exports, math };
  return _jsfxr;
}

let _zzfx = null;
export function loadZzfx() {
  if (_zzfx) return _zzfx;
  const math = seededMath();
  // zzfx.js creates an AudioContext at load (browser playback); stub it — we only call zzfxG.
  const sandbox = { window: { AudioContext: function () {} }, webkitAudioContext: function () {} };
  sandbox.Math = math;
  vm.createContext(sandbox);
  vm.runInContext(readFileSync(join(HERE, "vendor/zzfxm/zzfx.js"), "utf8"), sandbox, { filename: "zzfx.js" });
  vm.runInContext(readFileSync(join(HERE, "vendor/zzfxm/zzfxm.js"), "utf8"), sandbox, { filename: "zzfxm.js" });
  _zzfx = { ctx: sandbox, math };
  return _zzfx;
}

// JSON cannot express sparse arrays; ZzFX relies on `undefined` to pick defaults.
export function holesToUndefined(v) {
  if (Array.isArray(v)) return v.map((x) => (x === null ? undefined : holesToUndefined(x)));
  return v;
}

/** Render one recipe to mono Float samples (deterministic). */
export function renderSfx(recipe) {
  if (!recipe || typeof recipe !== "object") throw new Error("recipe must be an object");
  const seed = Number.isInteger(recipe.seed) ? recipe.seed : 1;
  if (Array.isArray(recipe.zzfx)) {
    const { ctx, math } = loadZzfx();
    math.reseed(seed);
    ctx.zzfxR = SAMPLE_RATE;
    if (typeof recipe.volume === "number") ctx.zzfxV = recipe.volume; else ctx.zzfxV = 0.3;
    return Array.from(ctx.zzfxG(...holesToUndefined(recipe.zzfx)));
  }
  const { lib, math } = loadJsfxr();
  math.reseed(seed);
  const p = new lib.Params();
  if (recipe.preset !== undefined) {
    if (!PRESETS.includes(recipe.preset)) throw new Error(`unknown preset "${recipe.preset}" (have: ${PRESETS.join(", ")})`);
    p[recipe.preset]();
  } else if (recipe.sfxr && typeof recipe.sfxr === "object") {
    p.fromJSON(recipe.sfxr);
  } else {
    throw new Error('recipe needs one of "preset", "zzfx", or "sfxr"');
  }
  if (recipe.overrides) p.fromJSON(recipe.overrides);
  p.sound_vol = typeof recipe.volume === "number" ? recipe.volume : (recipe.sfxr?.sound_vol ?? 0.25);
  p.sample_rate = SAMPLE_RATE;
  p.sample_size = 16;
  math.reseed(seed ^ 0x5f3759df); // noise buffer draws are seeded too
  const fx = new lib.SoundEffect(p);
  // Upstream can emit a stray NaN at an envelope edge (e.g. preset "tone", decay 0): zero it.
  return Array.from(fx.getRawBuffer().normalized, (v) => (Number.isFinite(v) ? v : 0));
}

export function sfxWav(recipe) {
  return encodeWav([renderSfx(recipe)], SAMPLE_RATE);
}

export function audioDir(id, root = REPO_ROOT) {
  if (!/^[A-Za-z0-9._-]+$/.test(id)) throw new Error(`bad game id "${id}"`);
  return join(root, "games", id, "audio");
}

function checkName(name) {
  if (!/^[A-Za-z0-9_-]+$/.test(name)) throw new Error(`bad clip name "${name}"`);
}

export function genOne(id, name, recipe, root = REPO_ROOT) {
  checkName(name);
  const dir = audioDir(id, root);
  mkdirSync(dir, { recursive: true });
  const out = join(dir, `${name}.wav`);
  const wav = sfxWav(recipe);
  writeFileSync(out, wav);
  return { out, bytes: wav.length, seconds: (wav.length - 44) / 2 / SAMPLE_RATE };
}

export function genBatch(id, recipesDoc, root = REPO_ROOT) {
  const list = Array.isArray(recipesDoc) ? recipesDoc : recipesDoc.recipes;
  if (!Array.isArray(list)) throw new Error('recipes file needs a "recipes" array');
  const results = [];
  for (const r of list) {
    if (r.kind === "music") continue;
    results.push({ name: r.name, ...genOne(id, r.name, r.synth ?? r, root) });
  }
  return results;
}

function main(argv) {
  const [cmd, ...rest] = argv;
  if (cmd === "presets") { console.log(PRESETS.join("\n")); return 0; }
  if (cmd === "gen" && rest.length === 3) {
    const r = genOne(rest[0], rest[1], JSON.parse(rest[2]));
    console.log(`wrote ${r.out} (${r.seconds.toFixed(3)} s)`);
    return 0;
  }
  if (cmd === "gen-batch" && rest.length === 2) {
    for (const r of genBatch(rest[0], JSON.parse(readFileSync(rest[1], "utf8"))))
      console.log(`wrote ${r.out} (${r.seconds.toFixed(3)} s)`);
    return 0;
  }
  console.error("usage: node tools/sfx.mjs gen <id> <name> '<json>' | gen-batch <id> <recipes.json> | presets");
  return 2;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exit(main(process.argv.slice(2)));
}
