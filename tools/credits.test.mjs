// Keeps games/towerdef-0001/data/CreditsDB.gd in sync with third_party/README.md.
// Every source the README marks as used (not "Planned", not ideas-only) must be
// credited in-game; CC-BY sources must carry a per-item attribution.
import { readFileSync } from 'node:fs';
import { describe, it, expect } from 'vitest';

const readme = readFileSync(new URL('../third_party/README.md', import.meta.url), 'utf8');
const credits = readFileSync(new URL('../games/towerdef-0001/data/CreditsDB.gd', import.meta.url), 'utf8').toLowerCase();

const rows = readme.split('\n')
  .filter((l) => l.startsWith('|') && !l.startsWith('|---') && !l.startsWith('| Name'))
  .map((l) => l.split('|').slice(1, -1).map((c) => c.trim()))
  .map(([name, url, license, taken]) => ({ name, url, license, taken }));

const used = rows.filter((r) => !/^planned/i.test(r.taken) && !/ideas only/i.test(r.taken));

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
