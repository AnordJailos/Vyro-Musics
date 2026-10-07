import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { test } from 'node:test';
import { buildReport, parseRequirements } from './progress.mjs';

const SAMPLE = `# Doc

**Version 9.9 · 1 January 2027 · Status: for review**

### AAA: First module

- [ ] **AAA-01** [M] First thing.
- [ ] **AAA-02** [2] Second thing | with a pipe.

### BBB: Second module

- [ ] **BBB-01** [3] Third thing.
`;

test('reads the version, modules, ids, phases and text', () => {
  const r = parseRequirements(SAMPLE);
  assert.equal(r.version, '9.9');
  assert.deepEqual(r.modules.map((m) => [m.code, m.items.length]), [['AAA', 2], ['BBB', 1]]);
  assert.deepEqual(r.modules[0].items[1], { id: 'AAA-02', phase: '2', text: 'Second thing | with a pipe.' });
});

test('counts statuses, treats unlisted items as not started, and escapes table pipes', () => {
  const report = buildReport(parseRequirements(SAMPLE), {
    meta: { updated: 'today', next: ['Do the thing'] },
    items: { 'AAA-01': { status: 'done', note: 'ok' }, 'AAA-02': { status: 'partial', note: 'half' } },
  });
  assert.match(report, /\| Done \| 1 \| 33% \|/);
  assert.match(report, /\| Partial \| 1 \| 33% \|/);
  assert.match(report, /\| Not started \| 1 \| 33% \|/);
  assert.match(report, /\*\*BBB\*\* \(1\): BBB-01/);
  assert.match(report, /Second thing \\\| with a pipe\./);
  assert.match(report, /1\. Do the thing/);
});

test('refuses ids that are not in the requirements document, and unknown statuses', () => {
  const reqs = parseRequirements(SAMPLE);
  assert.throws(() => buildReport(reqs, { items: { 'ZZZ-01': { status: 'done' } } }), /ZZZ-01/);
  assert.throws(() => buildReport(reqs, { items: { 'AAA-01': { status: 'finished' } } }), /unknown status/);
});

test('the real tracker matches the real requirements document and docs/progress.md is up to date', async () => {
  const root = join(import.meta.dirname, '..');
  const reqs = parseRequirements(await readFile(join(root, 'docs/requirements.md'), 'utf8'));
  const status = JSON.parse(await readFile(join(root, 'docs/status.json'), 'utf8'));
  const report = buildReport(reqs, status); // throws if status.json mentions an unknown id or status
  assert.ok(reqs.modules.flatMap((m) => m.items).length > 300);
  assert.equal(await readFile(join(root, 'docs/progress.md'), 'utf8'), report, 'run: node tools/progress.mjs');
});
