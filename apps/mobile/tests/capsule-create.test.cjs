/* global __dirname */
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const ts = require('typescript');
function load(file, dependencies) {
  const filename = path.resolve(__dirname, '..', file);
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX } }).outputText;
  const mod = new Module(filename, module); mod.filename = filename; mod.paths = module.paths;
  mod.require = (id) => dependencies[id] ?? require(id); mod._compile(output, filename); return mod.exports;
}
class ApiError extends Error { constructor(kind, status) { super(kind); this.kind = kind; this.status = status; } }
const { validateDraft, localInstant, CapsuleSubmission } = load('lib/capsule-create.ts', { './api': { ApiError }, './capsules': {} });
const draft = { title: 'Title', body: 'private', date: '2026-03-09', time: '12:30' };
const now = Date.parse('2026-03-01T00:00:00Z');

test('validates blank, NUL and Unicode code point length', () => {
  process.env.TZ = 'UTC';
  assert.equal(validateDraft({ ...draft, title: ' ' }, now).ok, false);
  assert.equal(validateDraft({ ...draft, body: '\0' }, now).ok, false);
  assert.equal(validateDraft({ ...draft, body: '😀'.repeat(2000) }, now).ok, true);
  assert.equal(validateDraft({ ...draft, body: '😀'.repeat(2001) }, now).ok, false);
  assert.equal(validateDraft({ ...draft, date: '2026-02-30' }, now).ok, false);
  assert.equal(validateDraft(draft, Date.parse('2026-03-10T00:00:00Z')).ok, false);
  assert.equal(validateDraft(draft, Date.parse('2025-01-01T00:00:00Z')).ok, false);
});

test('generates UTC ISO and rejects daylight saving gap and fold', () => {
  process.env.TZ = 'America/New_York';
  assert.equal(localInstant('2026-03-08', '02:30'), null);
  assert.equal(localInstant('2026-11-01', '01:30'), null);
  const result = validateDraft(draft, now);
  assert.equal(result.ok, true);
  assert.equal(result.request.unlock_at, '2026-03-09T16:30:00.000Z');
  process.env.TZ = 'Australia/Lord_Howe';
  assert.equal(localInstant('2026-04-05', '01:45'), null);
  process.env.TZ = 'UTC';
});

test('submission prevents duplicates and locks uncertain outcomes', async () => {
  let resolve; let calls = 0;
  const wait = new Promise((done) => { resolve = done; });
  const submitter = new CapsuleSubmission('A', async (_user, _signal, request) => { calls++; assert.equal(request.body, 'private'); return wait; });
  const request = { title: 'Title', body: 'private', unlock_at: '2026-03-09T12:30:00.000Z' };
  const first = submitter.submit(request);
  assert.equal(await submitter.submit(request), null); assert.equal(calls, 1);
  resolve({}); assert.equal(await first, 'success');
  for (const error of [new ApiError('timeout'), new ApiError('network'), new ApiError('response', 503), new ApiError('response')]) {
    const uncertain = new CapsuleSubmission('A', async () => { throw error; });
    assert.equal(await uncertain.submit(request), 'uncertain');
    assert.equal(await uncertain.submit(request), null);
  }
  assert.equal(await new CapsuleSubmission('A', async () => { throw new ApiError('response', 422); }).submit(request), 'invalid');
  assert.equal(await new CapsuleSubmission('A', async () => { throw new ApiError('unauthorized', 403); }).submit(request), 'auth');
});

test('dispose aborts and suppresses a stale successful submission', async () => {
  let resolve; let signal;
  const submitter = new CapsuleSubmission('A', (_user, s) => { signal = s; return new Promise((done) => { resolve = done; }); });
  const pending = submitter.submit({ title: 'Title', body: 'private', unlock_at: '2026-03-09T12:30:00Z' });
  submitter.dispose(); assert.equal(signal.aborted, true); resolve({});
  assert.equal(await pending, 'cancelled');
});

test('successful screen submission clears message and replaces route with fresh list', async () => {
  const values = []; let cursor = 0; let effectRun = false; let destination;
  const mockReact = {
    useState(initial) { const index = cursor++; if (!(index in values)) values[index] = initial; return [values[index], (value) => { values[index] = value; }]; },
    useRef(initial) { const index = cursor++; if (!(index in values)) values[index] = { current: initial }; return values[index]; },
    useEffect(callback) { if (!effectRun) { effectRun = true; callback(); } },
  };
  let submitted;
  class MockSubmission { async submit(request) { submitted = request; return 'success'; } dispose() {} }
  const native = { Text: 'Text', TextInput: 'TextInput' };
  const fakeUi = { Screen: 'Screen', Action: 'Action', styles: { title: {}, label: {}, input: {}, text: {}, error: {} } };
  const local = new Date('2027-01-01T12:00:00Z');
  const screen = load('app/create-capsule.tsx', { react: mockReact, 'react-native': native,
    'expo-router': { router: { replace: (value) => { destination = value; } } }, '../components/ui': fakeUi,
    '../lib/auth': { useAuth: () => ({ session: { user: { id: 'A' } } }) },
    '../lib/capsule-create': { CapsuleSubmission: MockSubmission, validateDraft: (input) => ({ ok: true, local, request: { title: input.title, body: input.body, unlock_at: local.toISOString() } }) } }).default;
  const element = screen();
  function render() { cursor = 0; return element.type(element.props); }
  function find(element, title) {
    if (!element || typeof element !== 'object') return undefined;
    if (element.type === 'Action' && element.props.title === title) return element;
    const children = element.props?.children;
    for (const child of Array.isArray(children) ? children : [children]) { const result = find(child, title); if (result) return result; }
  }
  render(); values[0] = 'Title'; values[1] = 'private';
  find(render(), 'Review capsule').props.onPress();
  find(render(), 'Seal capsule').props.onPress();
  await Promise.resolve(); await Promise.resolve();
  assert.equal(submitted.body, 'private');
  assert.equal(values[1], '');
  assert.equal(destination, '/capsules');
});
