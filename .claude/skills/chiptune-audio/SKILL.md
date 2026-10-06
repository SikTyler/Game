---
name: chiptune-audio
description: Use when a playable Godot game needs event SFX plus a looping music track but no GPU/ComfyUI is available (CI, cloud sessions, laptops), or when the concept's theme suits retro/arcade/synth sound. GPU-free procedural path — derives an audio system from concept.theme, maps engine events to jsfxr (sfxr) presets/params or ZzFX arrays, renders deterministic WAVs via tools/sfx.mjs, authors a ZzFXM song rendered loop-exact via tools/music.mjs, wires a pooled, rate-limited Sfx player on Music/SFX buses, and records audio_pass {method:"procedural"}. Alternate method to the `audio` skill; hands off to validator.
---

# Chiptune audio (procedural, GPU-free)

Same contract as the `audio` skill (inputs, terminal status `scored`, `audio_pass` is the source of truth) but every clip is synthesized from numbers, so it is deterministic, tiny, and runs anywhere Node 18+ runs. Synths are vendored unmodified under `tools/vendor/` (jsfxr: Unlicense, ZzFX/ZzFXM: MIT — see `third_party/README.md`); they run in a `node:vm` sandbox whose `Math.random` is a seeded PRNG, so **same recipe ⇒ identical bytes**.

## Inputs
- `games/<id>/manifest.json` with `concept.theme` (premise, tone, palette words) and a running game whose rules engine emits events/signals.

## Outputs
- `games/<id>/audio/recipes.json`, `games/<id>/audio/*.wav`, `games/<id>/audio/<song>.song.json`
- An `Sfx` player script + bus layout in the game; `manifest.audio_pass` with `method: "procedural"`.

## 1. Derive the audio system (once)
From `concept.theme` write one line of `sonic_character` (e.g. "bright square-wave arcade, short and dry; low noise thumps for impacts"). Pick:
- **Waveform family:** square (0) = arcade/punchy, sawtooth (1) = aggressive/sci-fi, sine (2) = soft/cozy, noise (3) = impacts/explosions.
- **Pitch register:** cozy/small → higher `p_base_freq` (0.4–0.6); heavy/menacing → low (0.1–0.25).
- **Length budget:** UI blips ≤ 0.1 s, hits ≤ 0.25 s, rewards ≤ 0.5 s, big moments ≤ 1.2 s.
Keep every clip in the same family/register so the set sounds like one game.

## 2. Map engine events to presets
Read the engine's event list (never invent events the view must fabricate). Starting map:

| Event kind | jsfxr preset | Notes |
|---|---|---|
| shot / projectile fired | `laserShoot` | high rate → keep ≤ 0.12 s, volume ≤ 0.15 |
| enemy hit | `hitHurt` | |
| enemy killed / boss down | `explosion` | boss: lower `p_base_freq`, longer sustain |
| currency pickup | `pickupCoin` | |
| upgrade / level-up / prestige | `powerUp` | |
| UI press / tab | `blipSelect` or `click` | |
| wave start / alert | `tone` or `synth` | |
| failure / core destroyed | `explosion` + slide down (`p_freq_ramp` < 0) | |
Tweak with `overrides` (any sfxr param key) instead of hand-writing full params; use `{"zzfx":[...]}` when you want a ZzFX designer sound (JSON `null` = ZzFX's "use default" hole).

## 3. Write recipes, render
`games/<id>/audio/recipes.json`:
```json
{"recipes":[
  {"name":"shoot","kind":"sfx","synth":{"preset":"laserShoot","seed":3,"volume":0.15,"overrides":{"p_env_decay":0.08}}},
  {"name":"theme","kind":"music","song":"audio/theme.song.json"}
]}
```
```
node tools/sfx.mjs presets
node tools/sfx.mjs gen-batch <id> games/<id>/audio/recipes.json   # music entries skipped
node tools/sfx.mjs gen <id> coin '{"preset":"pickupCoin","seed":4}' # one-off audition
```
Output: 16-bit mono 44.1 kHz WAV. Change `seed` to audition variants; commit the recipe, not just the WAV.

## 4. Author the song
ZzFXM format (`[instruments, patterns, sequence, bpm]` or the object form `{instruments, patterns, sequence, bpm, seed, volume}`). Instruments are ZzFX arrays; each pattern is channels `[instrument, pan, note, note, ...]` (note 0 = rest, 1..n semitones). Keep it short (4–8 patterns, 8–32 rows), mood-matched bpm (idle/cozy 90–110, action 130–160), and low volume (≈0.2) so SFX sit on top. Upstream example songs (scratchpad `oss/ZzFXM/examples/songs/`) are a format reference only.
```
node tools/music.mjs render <id> theme games/<id>/audio/theme.song.json
```
The WAV is stereo and **loop-exact**: its length equals the sequence length and release tails wrap onto the start, so import with loop forward / `loop_offset 0` and there is no seam.

## 5. Wire into Godot (engine rules stay in the engine)
- Buses in `default_bus_layout.tres`: `Master` → `Music`, `SFX`. Expose volume via `AudioServer.set_bus_volume_db`; persist in the game's settings, not an autoload.
- One `Sfx.gd` (preloaded class, static helpers OK; **no autoload**): a pool of N `AudioStreamPlayer` (N≈8) on bus `SFX`, round-robin; per-clip **rate limit** (min interval, e.g. shoot 60 ms, hit 40 ms, UI 0) and a per-frame cap so a 50-enemy kill burst does not clip. Slight pitch jitter (±3%) from a seeded RNG is fine.
- Music: one looping `AudioStreamPlayer` on bus `Music`.
- The view subscribes to engine events and calls `Sfx.play(&"clip")`; the engine never references audio. Strict typing throughout.
- Re-import (`--import`) so `.wav.import` files exist; set `edit/loop_mode=1` for the music import.

## 6. Record `audio_pass`, hand off
```json
"audio_pass": {"method":"procedural",
  "audio_system":{"model":"jsfxr+zzfx+zzfxm","sonic_character":"..."},
  "recipes":[{"name":"shoot","kind":"sfx","synth":{...},"format":"wav","loop":false},
             {"name":"theme","kind":"music","song":"audio/theme.song.json","format":"wav","loop":true}],
  "events":[{"event":"shot_fired","clip":"shoot","node":"Sfx","signal":"shot_fired"}],
  "notes":"..."}
```
Merge it via the manifest tool, then `node tools/manifest.mjs set-status <id> scored`, then run `validator` (headless boot must show no errors from audio nodes) and, if available, a human listen.
