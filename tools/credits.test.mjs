// Keeps the in-game CreditsDB.gd files in sync with third_party/README.md.
// Every source the README marks as used (not "Planned", not ideas-only) must be
// credited in-game; CC-BY sources must carry a per-item attribution.
// Rows above the "## Corehold PC edition" heading apply to BOTH the mobile game
// and its PC fork; rows under it apply to the PC game only.
import { readFileSync } from 'node:fs';
import { describe, it, expect } from 'vitest';

const readme = readFileSync(new URL('../third_party/README.md', import.meta.url), 'utf8');
const credits = readFileSync(new URL('../games/towerdef-0001/data/CreditsDB.gd', import.meta.url), 'utf8').toLowerCase();
const pcCredits = readFileSync(new URL('../games/towerdef-pc-0001/data/CreditsDB.gd', import.meta.url), 'utf8').toLowerCase();
const PC_HEADING = '## Corehold PC edition';
const [sharedPart, pcPart = ''] = readme.split(PC_HEADING);

const parseRows = (text) => text.split('\n')
  .filter((l) => l.startsWith('|') && !l.startsWith('|---') && !l.startsWith('| Name'))
  .map((l) => l.split('|').slice(1, -1).map((c) => c.trim()))
  .map(([name, url, license, taken]) => ({ name, url, license, taken }));
const isUsed = (r) => !/^planned/i.test(r.taken) && !/ideas only/i.test(r.taken);

const rows = parseRows(sharedPart);
const used = rows.filter(isUsed);
const pcUsed = parseRows(pcPart).filter(isUsed);

describe('in-game credits mirror third_party/README.md', () => {
  it('parses the source table', () => {
    expect(rows.length).toBeGreaterThanOrEqual(5);
    expect(used.length).toBeGreaterThanOrEqual(5);
  });
  for (const r of used) {
    it(`credits ${r.name}`, () => {
      const key = r.name.split(/\s+/)[0].toLowerCase();
      expect(credits, `CreditsDB.gd is missing "${key}" (README row ${r.name})`).toContain(key);
      expect(credits).toContain(r.license.split(/[;( ]/)[0].toLowerCase().replace('code', 'mit'));
    });
  }
  it('CC-BY sources in use have attribution lines (game-icons: one per icon)', () => {
    for (const r of used.filter((x) => /cc-by|cc by/i.test(x.license) && !/^code/i.test(x.license))) {
      expect(credits).toContain('cc by');
      if (/game-icons/i.test(r.name)) expect(credits).toMatch(/icons? by .+ from game-icons\.net/);
    }
  });
});

describe('PC credits mirror third_party/README.md (shared + PC rows)', () => {
  it('has a PC section with rows', () => {
    expect(pcUsed.length).toBeGreaterThanOrEqual(4);
  });
  for (const r of [...used, ...pcUsed]) {
    it(`PC credits ${r.name}`, () => {
      const key = r.name.split(/\s+/)[0].toLowerCase();
      expect(pcCredits, `PC CreditsDB.gd is missing "${key}" (README row ${r.name})`).toContain(key);
      expect(pcCredits).toContain(r.license.split(/[;( ]/)[0].toLowerCase().replace('code', 'mit'));
    });
  }
  it('credits Xelu, Maaack, Nathan Hoad and the Godot demo contributors (PC-S6)', () => {
    for (const k of ['xelu', 'maaack', 'nathan hoad', 'godot-demo-projects']) expect(pcCredits).toContain(k);
  });
});
