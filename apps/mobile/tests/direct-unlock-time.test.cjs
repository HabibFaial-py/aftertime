/* global __dirname */
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const ts = require('typescript');

function load(file, dependencies) {
  const filename = path.resolve(__dirname, '..', file);
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS },
  }).outputText;
  const mod = new Module(filename, module);
  mod.filename = filename; mod.paths = module.paths;
  mod.require = (id) => dependencies[id] ?? require(id);
  mod._compile(output, filename);
  return mod.exports;
}

const self = load('lib/capsule-create.ts', { './api': {}, './capsules': {} });
const { validateDirectUnlockTime: check, isDirectTimeReviewCurrent } = load('lib/direct-unlock-time.ts', { './capsule-create': self });
const day = 86400000;

function inZone(zone, run) {
  const previous = process.env.TZ;
  try { process.env.TZ = zone; run(); }
  finally { if (previous === undefined) delete process.env.TZ; else process.env.TZ = previous; }
}

test('strictly parses calendar dates and 24-hour minute fields', () => inZone('UTC', () => {
  const now = Date.parse('2028-01-01T00:00:00Z');
  for (const [date, time] of [
    ['2028-02-30', '12:00'], ['2027-02-29', '12:00'], ['2028-04-31', '12:00'],
    ['2028-00-01', '12:00'], ['2028-13-01', '12:00'], ['2028-01-00', '12:00'],
    ['2028-1-01', '12:00'], ['2028-01-01 ', '12:00'], ['2028-01-01', '24:00'],
    ['2028-01-01', '12:60'], ['2028-01-01', '1:00'], ['2028-01-01', '12:00:00'],
  ]) assert.match(check(date, time, now).error, /valid, unambiguous/);
  assert.deepEqual(check('2028-02-29', '12:00', now), {
    ok: true, utc: '2028-02-29T12:00:00.000Z', offset: 'UTC+00:00',
  });
}));

test('uses strict future and inclusive 90 elapsed day boundaries', () => inZone('UTC', () => {
  const instant = Date.parse('2028-03-01T12:00:00Z');
  for (const now of [instant, instant + 1, instant - 90 * day - 1]) {
    assert.match(check('2028-03-01', '12:00', now).error, /future within 90 days/);
  }
  for (const now of [instant - 1, instant - 90 * day, instant - 90 * day + 1]) {
    assert.equal(check('2028-03-01', '12:00', now).utc, '2028-03-01T12:00:00.000Z');
  }
}));

test('serializes local times across day, month and year boundaries with offsets', () => {
  inZone('Asia/Kathmandu', () => {
    assert.deepEqual(check('2027-01-01', '00:15', Date.parse('2026-12-01T00:00:00Z')), {
      ok: true, utc: '2026-12-31T18:30:00.000Z', offset: 'UTC+05:45',
    });
  });
  inZone('America/New_York', () => {
    assert.deepEqual(check('2026-12-31', '23:30', Date.parse('2026-12-01T00:00:00Z')), {
      ok: true, utc: '2027-01-01T04:30:00.000Z', offset: 'UTC-05:00',
    });
    assert.equal(check('2026-03-01', '00:30', Date.parse('2026-02-01T00:00:00Z')).utc, '2026-03-01T05:30:00.000Z');
  });
});

test('rejects DST gaps and folds, including half-hour changes and a skipped day', () => {
  inZone('America/New_York', () => {
    const spring = Date.parse('2026-03-01T00:00:00Z');
    assert.equal(check('2026-03-08', '02:30', spring).ok, false);
    assert.equal(check('2026-03-08', '01:30', spring).utc, '2026-03-08T06:30:00.000Z');
    assert.equal(check('2026-03-08', '03:30', spring).utc, '2026-03-08T07:30:00.000Z');
    assert.equal(check('2026-11-01', '01:30', Date.parse('2026-10-01T00:00:00Z')).ok, false);
  });
  inZone('Australia/Lord_Howe', () => {
    assert.equal(check('2026-04-05', '01:45', Date.parse('2026-04-01T00:00:00Z')).ok, false);
    assert.equal(check('2026-10-04', '02:15', Date.parse('2026-10-01T00:00:00Z')).ok, false);
  });
  inZone('Pacific/Apia', () => {
    assert.equal(check('2011-12-30', '12:00', Date.parse('2011-12-01T00:00:00Z')).ok, false);
  });
});

test('review expires for clock changes, timezone changes and both time-window boundaries', () => inZone('UTC', () => {
  const wallClock = Date.parse('2028-01-01T12:00:00Z');
  const review = { date: '2028-01-02', time: '12:00', timezone: 'UTC', offset: 'UTC+00:00',
    utc: '2028-01-02T12:00:00.000Z', wallClock, monotonicClock: 5000 };
  const current = (now, monotonic = 5000, zone = 'UTC') => isDirectTimeReviewCurrent(review, now, monotonic, zone);
  assert.equal(current(wallClock), true);
  assert.equal(current(wallClock + 5000, 10000), true);
  assert.equal(current(wallClock + 5001, 10000), true);
  assert.equal(current(wallClock + 2000), false);
  assert.equal(current(wallClock - 2000), false);
  assert.equal(current(wallClock, 5000, 'Europe/London'), false);
  assert.equal(current(wallClock, 4999), false);
  const instant = Date.parse(review.utc);
  assert.equal(isDirectTimeReviewCurrent({ ...review, wallClock: instant - 1 }, instant - 1, 5000, 'UTC'), true);
  assert.equal(isDirectTimeReviewCurrent({ ...review, wallClock: instant }, instant, 5000, 'UTC'), false);
  assert.equal(isDirectTimeReviewCurrent({ ...review, wallClock: instant - 90 * day }, instant - 90 * day, 5000, 'UTC'), true);
  assert.equal(isDirectTimeReviewCurrent({ ...review, wallClock: instant - 90 * day - 1 }, instant - 90 * day - 1, 5000, 'UTC'), false);
  inZone('America/New_York', () => assert.equal(current(wallClock), false));
}));
