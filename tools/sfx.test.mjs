import { test, expect, describe } from "vitest";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { sfxWav, renderSfx, genOne, genBatch, PRESETS, SAMPLE_RATE } from "./sfx.mjs";
import { songWav, renderSong, loopLength, rowSamples, parseSongFile, renderToGame } from "./music.mjs";
import { encodeWav, readWavHeader, mulberry32 } from "./wav.mjs";

describe("wav.mjs", () => {
  test("encodeWav writes a canonical 16-bit PCM RIFF/WAVE header", () => {
    const h = readWavHeader(encodeWav([[0, 0.5, -0.5, 1]], 44100));
    expect(h).toMatchObject({ format: 1, channels: 1, sampleRate: 44100, bitsPerSample: 16, dataBytes: 8, riffSize: 44, frames: 4 });
  });
  test("clamps out-of-range samples instead of wrapping", () => {
    const b = encodeWav([[2, -2, NaN]], 44100);
    expect([b.readInt16LE(44), b.readInt16LE(46), b.readInt16LE(48)]).toEqual([32767, -32767, 0]);
  });
  test("readWavHeader rejects non-WAV bytes", () => {
    expect(() => readWavHeader(Buffer.alloc(60))).toThrow(/RIFF/);
  });
  test("mulberry32 is reproducible per seed", () => {
    const a = mulberry32(9), b = mulberry32(9), c = mulberry32(10);
    const xs = [a(), a(), a()];
    expect([b(), b(), b()]).toEqual(xs);
    expect(c()).not.toBe(xs[0]);
  });
});

describe("sfx.mjs", () => {
  test.each(PRESETS)("preset %s renders a non-silent 16-bit mono 44.1k WAV", (preset) => {
    const wav = sfxWav({ preset, seed: 5 });
    const h = readWavHeader(wav);
    expect(h).toMatchObject({ channels: 1, sampleRate: SAMPLE_RATE, bitsPerSample: 16 });
    expect(h.frames).toBeGreaterThan(100);
    const peak = renderSfx({ preset, seed: 5 }).reduce((m, v) => Math.max(m, Math.abs(v)), 0);
    expect(peak).toBeGreaterThan(0.001);
  });
  test("same recipe -> identical bytes; different seed -> different sound", () => {
    const a = sfxWav({ preset: "explosion", seed: 42 });
    expect(sfxWav({ preset: "explosion", seed: 42 }).equals(a)).toBe(true);
    expect(sfxWav({ preset: "explosion", seed: 43 }).equals(a)).toBe(false);
  });
  test("zzfx arrays (JSON nulls as holes) are deterministic", () => {
    const r = { zzfx: [1, 0.05, 440, null, 0.02, 0.1, 2], seed: 3 };
    const a = sfxWav(r);
    expect(readWavHeader(a).sampleRate).toBe(44100);
    expect(sfxWav(r).equals(a)).toBe(true);
  });
  test("full sfxr params + overrides are honoured", () => {
    const base = { wave_type: 0, p_env_sustain: 0.1, p_env_decay: 0.2, p_base_freq: 0.4 };
    const a = sfxWav({ sfxr: base });
    const b = sfxWav({ sfxr: base, overrides: { p_base_freq: 0.6 } });
    expect(a.equals(b)).toBe(false);
    expect(a.length).toBe(b.length);
  });
  test("rejects unknown presets and empty recipes", () => {
    expect(() => sfxWav({ preset: "nope" })).toThrow(/unknown preset/);
    expect(() => sfxWav({})).toThrow(/preset/);
  });
  test("gen / gen-batch write games/<id>/audio/<name>.wav and skip music recipes", () => {
    const root = mkdtempSync(join(tmpdir(), "sfx-"));
    const one = genOne("g-1", "coin", { preset: "pickupCoin", seed: 1 }, root);
    expect(one.out).toBe(join(root, "games", "g-1", "audio", "coin.wav"));
    const res = genBatch("g-1", { recipes: [
      { name: "hit", kind: "sfx", synth: { preset: "hitHurt", seed: 2 } },
      { name: "theme", kind: "music", song: "x.json" },
    ] }, root);
    expect(res.map((r) => r.name)).toEqual(["hit"]);
    expect(readWavHeader(readFileSync(join(root, "games/g-1/audio/hit.wav"))).channels).toBe(1);
    expect(() => genOne("../evil", "x", { preset: "click" }, root)).toThrow(/bad game id/);
    expect(() => genOne("g-1", "a/b", { preset: "click" }, root)).toThrow(/bad clip name/);
  });
});

const SONG = {
  bpm: 120, seed: 1,
  instruments: [[0.6, 0, 220, null, null, 0.3, 2], [0.4, 0, 110, null, null, 0.5]],
  patterns: [
    [[0, 0, 13, null, 17, null, 20, null, 17, null], [1, 0, 1, null, null, null, 8, null, null, null]],
    [[0, 0, 15, null, 18, null, 22, null, 25, null]],
  ],
  sequence: [0, 1, 0],
};

describe("music.mjs", () => {
  test("renders stereo 16-bit 44.1k with loop-exact length", () => {
    const wav = songWav(SONG);
    const h = readWavHeader(wav);
    expect(h).toMatchObject({ channels: 2, sampleRate: 44100, bitsPerSample: 16 });
    expect(loopLength(SONG)).toBe(3 * 8 * rowSamples(120));
    expect(h.frames).toBe(loopLength(SONG));
    expect(renderSong(SONG).seconds).toBeCloseTo(h.frames / 44100, 6);
  });
  test("is deterministic", () => {
    expect(songWav(SONG).equals(songWav(SONG))).toBe(true);
  });
  test("accepts the raw ZzFXM array form and JS array literals", () => {
    const arr = [SONG.instruments, SONG.patterns, SONG.sequence, 120];
    expect(songWav(arr).length).toBe(songWav(SONG).length);
    const lit = parseSongFile("[[[.5,0,220,,,.2]],[[[0,0,13,,15,]]],[0],100];");
    expect(readWavHeader(songWav(lit)).frames).toBe(3 * rowSamples(100)); // trailing comma is not a hole;
  });
  test("renderToGame writes games/<id>/audio/<name>.wav", () => {
    const root = mkdtempSync(join(tmpdir(), "mus-"));
    const r = renderToGame("g-2", "theme", SONG, root);
    expect(readWavHeader(readFileSync(r.out)).channels).toBe(2);
    writeFileSync(join(root, "noop"), "");
  });
});
