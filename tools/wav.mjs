// Minimal deterministic PCM WAV encode/decode shared by tools/sfx.mjs + tools/music.mjs.
// 16-bit little-endian PCM, 1..N interleaved channels. Pure (no I/O) so it is unit-testable.

// Float samples in [-1,1] -> Int16 (clamped). Math.round keeps it symmetric + deterministic.
function toInt16(x) {
  const v = Number.isFinite(x) ? x : 0;
  const c = v > 1 ? 1 : v < -1 ? -1 : v;
  return Math.round(c * 32767);
}

/** channels: Array<ArrayLike<number>> (all same length). Returns a Buffer holding a RIFF/WAVE file. */
export function encodeWav(channels, sampleRate = 44100) {
  const nch = channels.length;
  if (nch < 1) throw new Error("encodeWav: need at least one channel");
  const frames = channels[0].length;
  for (const ch of channels) if (ch.length !== frames) throw new Error("encodeWav: channel length mismatch");
  const dataBytes = frames * nch * 2;
  const buf = Buffer.alloc(44 + dataBytes);
  buf.write("RIFF", 0, "ascii");
  buf.writeUInt32LE(36 + dataBytes, 4);
  buf.write("WAVE", 8, "ascii");
  buf.write("fmt ", 12, "ascii");
  buf.writeUInt32LE(16, 16);            // fmt chunk size
  buf.writeUInt16LE(1, 20);             // PCM
  buf.writeUInt16LE(nch, 22);
  buf.writeUInt32LE(sampleRate, 24);
  buf.writeUInt32LE(sampleRate * nch * 2, 28); // byte rate
  buf.writeUInt16LE(nch * 2, 32);       // block align
  buf.writeUInt16LE(16, 34);            // bits per sample
  buf.write("data", 36, "ascii");
  buf.writeUInt32LE(dataBytes, 40);
  let o = 44;
  for (let i = 0; i < frames; i++) {
    for (let c = 0; c < nch; c++) { buf.writeInt16LE(toInt16(channels[c][i]), o); o += 2; }
  }
  return buf;
}

/** Parse the canonical 44-byte header written by encodeWav (throws on anything else). */
export function readWavHeader(buf) {
  if (buf.length < 44 || buf.toString("ascii", 0, 4) !== "RIFF" || buf.toString("ascii", 8, 12) !== "WAVE")
    throw new Error("not a RIFF/WAVE file");
  if (buf.toString("ascii", 12, 16) !== "fmt " || buf.toString("ascii", 36, 40) !== "data")
    throw new Error("unexpected WAV chunk layout");
  const channels = buf.readUInt16LE(22);
  const sampleRate = buf.readUInt32LE(24);
  const bitsPerSample = buf.readUInt16LE(34);
  const dataBytes = buf.readUInt32LE(40);
  return {
    format: buf.readUInt16LE(20), channels, sampleRate, bitsPerSample, dataBytes,
    riffSize: buf.readUInt32LE(4),
    frames: dataBytes / (channels * (bitsPerSample / 8)),
    durationS: dataBytes / (channels * (bitsPerSample / 8)) / sampleRate,
  };
}

/** mulberry32: tiny seeded PRNG in [0,1). Replaces Math.random inside vendored synths. */
export function mulberry32(seed) {
  let a = (seed >>> 0) || 0x9e3779b9;
  return function () {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** A Math object whose random() draws from a swappable seeded RNG (for vm sandboxes). */
export function seededMath() {
  const m = Object.create(Math);
  let rng = mulberry32(1);
  m.random = () => rng();
  m.reseed = (seed) => { rng = mulberry32(seed); };
  return m;
}
