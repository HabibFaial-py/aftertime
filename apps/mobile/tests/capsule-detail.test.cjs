/* global __dirname */
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const ts = require('typescript');
function load(file, dependencies, imports = []) {
  const filename = path.resolve(__dirname, '..', file);
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX } }).outputText;
  const mod = new Module(filename, module); mod.filename = filename; mod.paths = module.paths;
  mod.require = (id) => { imports.push(id); return dependencies[id] ?? require(id); }; mod._compile(compiled, filename); return mod.exports;
}
class ApiError extends Error { constructor(kind, status) { super(kind); this.kind = kind; this.status = status; } }
const detail = load('lib/capsule-detail.ts', { './api': { ApiError }, './capsules': {} });
const id = 'e3216d4c-9b6e-4f8b-8493-7e3a3ac7da80';
const item = (identifier = id) => ({ id: identifier, title: 'Title', status: 'locked', unlock_at: '2026-11-14T10:00:00Z', created_at: '2026-11-13T10:00:00Z' });
const pending = () => { let resolve; const promise = new Promise((done) => { resolve = done; }); return { promise, resolve }; };

test('UUID validation and unavailable metadata do not call reveal', async () => {
  assert.equal(detail.validCapsuleId(id), true);
  for (const value of ['../bad', '', [id], null]) assert.equal(detail.validCapsuleId(value), false);
  let calls = 0; const states = [];
  const invalid = new detail.CapsuleDetailController('A', '../bad', (s) => states.push(s), async () => { calls++; return []; }, async () => { calls++; });
  await invalid.load(); await invalid.reveal();
  assert.equal(calls, 0); assert.equal(states.at(-1).phase, 'unavailable');
  const missing = new detail.CapsuleDetailController('A', id, (s) => states.push(s), async () => [], async () => { calls++; });
  await missing.load(); assert.equal(states.at(-1).phase, 'unavailable'); assert.equal(calls, 0);
});

test('metadata lookup searches later pages without automatic reveal', async () => {
  const offsets = []; let revealCalls = 0; const states = [];
  const controller = new detail.CapsuleDetailController('A', id, (s) => states.push(s), async (_user, _signal, limit, offset) => {
    assert.equal(limit, 50); offsets.push(offset);
    return offset === 0 ? Array.from({ length: 50 }, () => item('f3216d4c-9b6e-4f8b-8493-7e3a3ac7da80')) : [item()];
  }, async () => { revealCalls++; return { id, body: 'private' }; });
  await controller.load(); assert.deepEqual(offsets, [0, 50]);
  assert.equal(states.at(-1).phase, 'ready'); assert.equal(states.at(-1).body, null); assert.equal(revealCalls, 0);
  await controller.reveal(); assert.equal(revealCalls, 1); assert.equal(states.at(-1).phase, 'revealed'); assert.equal(states.at(-1).body, 'private');
});

test('safe reveal errors never include private response details', async () => {
  for (const error of [new ApiError('response', 404), new ApiError('unauthorized', 401), new ApiError('session'), new ApiError('response', 503), new ApiError('network'), new ApiError('timeout'), new ApiError('cancelled'), new ApiError('response')]) {
    const states = [];
    const controller = new detail.CapsuleDetailController('A', id, (s) => states.push(s), async () => [item()], async () => { throw error; });
    await controller.load(); await controller.reveal();
    assert.equal(states.at(-1).phase, 'error'); assert.equal(states.at(-1).body, null); assert.ok(states.at(-1).error);
    if (error.status === 404) assert.equal(states.at(-1).error, 'This capsule is unavailable.');
  }
});

test('dispose aborts and suppresses stale metadata and revealed message', async () => {
  const first = pending(); let listSignal; const oldStates = [];
  const old = new detail.CapsuleDetailController('A', id, (s) => oldStates.push(s), async (_user, signal) => { listSignal = signal; return first.promise; });
  const loading = old.load(); old.dispose(); assert.equal(listSignal.aborted, true);
  const oldCount = oldStates.length; first.resolve([item()]); await loading; assert.equal(oldStates.length, oldCount);
  const reveal = pending(); let revealSignal; const states = [];
  const current = new detail.CapsuleDetailController('B', id, (s) => states.push(s), async (user) => { assert.equal(user, 'B'); return [item()]; }, async (_user, signal) => { revealSignal = signal; return reveal.promise; });
  await current.load(); const work = current.reveal(); current.dispose(); assert.equal(revealSignal.aborted, true);
  const count = states.length; reveal.resolve({ id, body: 'private' }); await work; assert.equal(states.length, count);
});

test('detail controller has no persistent-storage dependency or calls during reveal', async () => {
  const imports = []; const writes = [];
  const storage = { setItem: (...args) => writes.push(args), setItemAsync: (...args) => writes.push(args) };
  const module = load('lib/capsule-detail.ts', { './api': { ApiError }, './capsules': {}, 'expo-secure-store': storage, '@react-native-async-storage/async-storage': storage }, imports);
  const controller = new module.CapsuleDetailController('A', id, () => {}, async () => [item()], async () => ({ id, body: 'private' }));
  await controller.load(); await controller.reveal(); controller.dispose();
  assert.deepEqual(imports, ['./api', './capsules']); assert.deepEqual(writes, []);
});

test('screen clears on blur, route/session changes remount, and body appears only after reveal', () => {
  let state = detail.emptyDetail(); let focus; let session = { user: { id: 'A' } }; let route = id;
  const react = { useState: () => [state, (next) => { state = typeof next === 'function' ? next() : next; }], useRef: () => ({ current: null }), useCallback: (fn) => fn };
  class MockController { load() {} reveal() {} dispose() {} }
  const screen = load('app/capsule/[id].tsx', { react, 'react-native': { Text: 'Text', ActivityIndicator: 'ActivityIndicator', Pressable: 'Pressable', StyleSheet: { create: (s) => s } },
    'expo-router': { router: {}, useFocusEffect: (fn) => { focus = fn; }, useLocalSearchParams: () => ({ id: route }) },
    '../../components/ui': { Screen: 'Screen', Action: 'Action', styles: { title: {}, label: {}, text: {}, error: {} } },
    '../../lib/auth': { useAuth: () => ({ session }) }, '../../lib/capsule-detail': { ...detail, CapsuleDetailController: MockController } }).default;
  const child = screen();
  let rendered = JSON.stringify(child.type(child.props)); assert.doesNotMatch(rendered, /private/);
  const cleanup = focus();
  state = { metadata: item(), phase: 'revealed', error: '', body: 'private' };
  rendered = JSON.stringify(child.type(child.props)); assert.match(rendered, /private/);
  cleanup(); assert.equal(state.body, null);
  route = 'f3216d4c-9b6e-4f8b-8493-7e3a3ac7da80'; assert.notEqual(screen().key, child.key);
  route = id; session = { user: { id: 'B' } }; assert.notEqual(screen().key, child.key);
  session = null; assert.equal(screen(), null);
});

test('cancellation requires confirmation, prevents duplicate requests and clears revealed state', async () => {
  const states = []; const done = pending(); let calls = 0;
  const controller = new detail.CapsuleDetailController('A', id, (s) => states.push(s), async () => [item()], async () => ({ id, body: 'private' }),
    async (_user, _signal, capsuleId) => { calls++; assert.equal(capsuleId, id); return done.promise; });
  await controller.load(); await controller.reveal();
  assert.equal(states.at(-1).body, 'private');
  assert.equal(await controller.confirmCancellation(), false); assert.equal(calls, 0);
  controller.requestCancellation(); assert.equal(states.at(-1).phase, 'confirmCancel'); assert.equal(calls, 0);
  controller.keepCapsule(); assert.equal(states.at(-1).phase, 'revealed');
  controller.requestCancellation();
  const first = controller.confirmCancellation();
  assert.equal(states.at(-1).phase, 'cancelling');
  assert.equal(await controller.confirmCancellation(), false); assert.equal(calls, 1);
  done.resolve({ id, cancelled_at: '2026-11-14T10:00:00Z' }); assert.equal(await first, true);
  assert.deepEqual(states.at(-1), { metadata: null, phase: 'cancelled', error: '', body: null });
  controller.requestCancellation(); await controller.reveal();
  assert.equal(states.at(-1).phase, 'cancelled'); assert.equal(calls, 1);
});

test('cancellation errors are safe and uncertain results block further actions', async () => {
  const cases = [
    [new ApiError('unauthorized', 401), 'error'], [new ApiError('session'), 'error'],
    [new ApiError('response', 404), 'error'], [new ApiError('response', 503), 'cancelUncertain'],
    [new ApiError('timeout'), 'cancelUncertain'], [new ApiError('network'), 'cancelUncertain'],
    [new ApiError('cancelled'), 'cancelUncertain'], [new ApiError('response'), 'cancelUncertain'],
  ];
  for (const [failure, expected] of cases) {
    const states = []; let calls = 0;
    const controller = new detail.CapsuleDetailController('A', id, (s) => states.push(s), async () => [item()], async () => ({ id, body: 'private' }), async () => { calls++; throw failure; });
    await controller.load(); await controller.reveal(); controller.requestCancellation();
    assert.equal(await controller.confirmCancellation(), false);
    assert.equal(states.at(-1).phase, expected); assert.equal(states.at(-1).body, null); assert.equal(calls, 1);
    if (failure.status === 404) assert.equal(states.at(-1).error, 'This capsule is unavailable.');
    if (expected === 'cancelUncertain') {
      assert.equal(states.at(-1).metadata, null); assert.match(states.at(-1).error, /may have succeeded.*Refresh/);
      controller.requestCancellation(); await controller.reveal(); await controller.confirmCancellation();
      assert.equal(calls, 1); assert.equal(states.at(-1).phase, 'cancelUncertain');
    }
  }
});

test('disposal aborts cancellation and discards late success', async () => {
  const result = pending(); const states = []; let signal;
  const controller = new detail.CapsuleDetailController('A', id, (s) => states.push(s), async () => [item()], async () => ({ id, body: 'private' }),
    async (_user, requestSignal) => { signal = requestSignal; return result.promise; });
  await controller.load(); controller.requestCancellation();
  const work = controller.confirmCancellation(); controller.dispose();
  assert.equal(signal.aborted, true); const count = states.length;
  result.resolve({ id, cancelled_at: '2026-11-14T10:00:00Z' });
  assert.equal(await work, false); assert.equal(states.length, count);
});

test('screen asks for confirmation and navigates to the refreshed list only on success', async () => {
  let state = detail.emptyDetail(); let focus; let destination; let calls = 0;
  const ref = { current: null };
  const react = { useState: () => [state, (next) => { state = typeof next === 'function' ? next() : next; }], useRef: () => ref, useCallback: (fn) => fn };
  class MockController extends detail.CapsuleDetailController {
    constructor(user, capsuleId, update) {
      super(user, capsuleId, update, async () => [item()], async () => ({ id, body: 'private' }), async () => { calls++; return { id, cancelled_at: '2026-11-14T10:00:00Z' }; });
    }
  }
  const screen = load('app/capsule/[id].tsx', { react, 'react-native': { Text: 'Text', ActivityIndicator: 'ActivityIndicator', Pressable: 'Pressable', StyleSheet: { create: (s) => s } },
    'expo-router': { router: { replace: (value) => { destination = value; } }, useFocusEffect: (fn) => { focus = fn; }, useLocalSearchParams: () => ({ id }) },
    '../../components/ui': { Screen: 'Screen', Action: 'Action', styles: { title: {}, label: {}, text: {}, error: {} } },
    '../../lib/auth': { useAuth: () => ({ session: { user: { id: 'A' } } }) }, '../../lib/capsule-detail': { ...detail, CapsuleDetailController: MockController } }).default;
  const child = screen();
  const render = () => child.type(child.props);
  function find(element, label) {
    if (!element || typeof element !== 'object') return undefined;
    if (element.type === 'Action' && element.props.title === label) return element;
    if (element.type === 'Pressable' && JSON.stringify(element.props.children).includes(label)) return element;
    const children = element.props?.children;
    for (const value of Array.isArray(children) ? children : [children]) { const result = find(value, label); if (result) return result; }
  }
  render(); const cleanup = focus(); await Promise.resolve(); await Promise.resolve();
  assert.equal(calls, 0);
  find(render(), 'Cancel capsule').props.onPress();
  assert.equal(calls, 0); assert.match(JSON.stringify(render()), /Cancellation is permanent/);
  find(render(), 'Confirm cancellation').props.onPress();
  await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
  assert.equal(calls, 1); assert.equal(destination, '/capsules');
  assert.equal(state.phase, 'cancelled'); assert.equal(state.metadata, null); assert.equal(state.body, null);
  assert.equal(find(render(), 'Reveal message'), undefined); assert.equal(find(render(), 'Cancel capsule'), undefined);
  cleanup();
});
