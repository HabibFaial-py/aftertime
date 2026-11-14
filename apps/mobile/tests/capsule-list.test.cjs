/* global __dirname */
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const ts = require('typescript');

function load(file, dependencies) {
  const filename = path.resolve(__dirname, '..', file);
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX },
  }).outputText;
  const mod = new Module(filename, module);
  mod.filename = filename;
  mod.paths = module.paths;
  mod.require = (id) => dependencies[id] ?? require(id);
  mod._compile(compiled, filename);
  return mod.exports;
}
class ApiError extends Error { constructor(kind) { super(kind); this.kind = kind; } }
const { CapsuleListController } = load('lib/capsule-list.ts', { './api': { ApiError }, './capsules': {} });
const item = (n) => ({ id: String(n), title: `Title ${n}`, status: 'locked', unlock_at: '2026-11-14T10:00:00Z', created_at: '2026-11-13T10:00:00Z' });
const deferred = () => { let resolve; let reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };

test('initial loading, empty and safe errors', async () => {
  const states = [];
  const pending = deferred();
  const controller = new CapsuleListController('A', (s) => states.push(s), () => pending.promise);
  const run = controller.refresh(true);
  assert.equal(states.at(-1).phase, 'loading');
  pending.resolve([]); await run;
  assert.equal(states.at(-1).phase, 'ready'); assert.deepEqual(states.at(-1).items, []);
  const failed = new CapsuleListController('A', (s) => states.push(s), async () => { throw new Error('private'); });
  await failed.refresh(true);
  assert.equal(states.at(-1).phase, 'error'); assert.doesNotMatch(states.at(-1).error, /private/);
  const unauthorized = new CapsuleListController('A', (s) => states.push(s), async () => { throw new ApiError('unauthorized'); });
  await unauthorized.refresh(true);
  assert.match(states.at(-1).error, /session/);
});

test('pagination uses raw offsets, deduplicates, and refresh replaces pages', async () => {
  const states = []; const offsets = [];
  const pages = [Array.from({ length: 50 }, (_, n) => item(n)), [item(49), item(50)], [item(80)]];
  const controller = new CapsuleListController('A', (s) => states.push(s), async (_user, _signal, limit, offset) => {
    assert.equal(limit, 50); offsets.push(offset); return pages.shift();
  });
  await controller.refresh(true); assert.equal(states.at(-1).hasMore, true);
  await controller.loadMore(); assert.equal(states.at(-1).items.length, 51);
  assert.equal(states.at(-1).hasMore, false);
  await controller.refresh();
  assert.deepEqual(offsets, [0, 50, 0]); assert.deepEqual(states.at(-1).items, [item(80)]);
});

test('refresh supersedes pending requests and disposal prevents account leakage', async () => {
  const states = []; const requests = [];
  const controller = new CapsuleListController('A', (s) => states.push(s), (_user, signal) => {
    const d = deferred(); requests.push({ ...d, signal }); return d.promise;
  });
  const old = controller.refresh(true); const fresh = controller.refresh();
  assert.equal(requests[0].signal.aborted, true);
  requests[1].resolve([item(2)]); await fresh;
  requests[0].resolve([item(1)]); await old;
  assert.deepEqual(states.at(-1).items, [item(2)]);
  const pending = controller.refresh(); controller.dispose();
  assert.equal(requests[2].signal.aborted, true);
  const count = states.length; requests[2].resolve([item(3)]); await pending;
  assert.equal(states.length, count);
  const otherStates = [];
  const other = new CapsuleListController('B', (s) => otherStates.push(s), async (user) => { assert.equal(user, 'B'); return []; });
  await other.refresh(true); assert.deepEqual(otherStates.at(-1).items, []);
});

test('list projection removes private fields and screen renders metadata only', async () => {
  let state;
  const controller = new CapsuleListController('A', (s) => { state = s; }, async () => [{ ...item(1), body: 'PRIVATE_MARKER' }]);
  await controller.refresh(true);
  assert.equal('body' in state.items[0], false);
  const fakeReact = { useState: () => [state, () => {}], useRef: () => ({ current: null }), useEffect: () => {} };
  const native = { FlatList: 'FlatList', ActivityIndicator: 'ActivityIndicator', Text: 'Text', View: 'View', Pressable: 'Pressable', StyleSheet: { create: (s) => s } };
  const ui = { Action: 'Action', styles: { screen: {}, title: {}, text: {}, error: {} } };
  let session = { user: { id: 'A' }, access_token: 'mock' };
  let destination;
  const screen = load('app/capsules.tsx', { react: fakeReact, 'react-native': native, 'expo-router': { router: { push: (value) => { destination = value; } } },
    'react-native-safe-area-context': { SafeAreaView: 'SafeAreaView' }, '../components/ui': ui,
    '../lib/auth': { useAuth: () => ({ session }) },
    '../lib/capsule-list': { CapsuleListController } }).default;
  const child = screen();
  assert.equal(screen().key, child.key);
  session = { user: { id: 'B' }, access_token: 'different-mock' };
  assert.notEqual(screen().key, child.key);
  session = null;
  assert.equal(screen(), null);
  const list = child.type(child.props).props.children;
  const card = list.props.renderItem({ item: state.items[0] });
  const rendered = JSON.stringify(card);
  assert.match(rendered, /Title 1/); assert.match(rendered, /Locked/); assert.match(rendered, /Reveal time/);
  assert.doesNotMatch(rendered, /PRIVATE_MARKER/);
  card.props.onPress();
  assert.deepEqual(destination, { pathname: '/capsule/[id]', params: { id: state.items[0].id } });
  state = { items: [], phase: 'loading', error: '', hasMore: false };
  assert.equal(child.type(child.props).props.children.props.ListEmptyComponent.props.accessibilityLabel, 'Loading capsules');
  state = { ...state, phase: 'ready' };
  assert.match(JSON.stringify(child.type(child.props).props.children.props.ListEmptyComponent), /no capsules/);
  state = { ...state, phase: 'error', error: 'Could not load' };
  assert.match(JSON.stringify(child.type(child.props).props.children.props.ListFooterComponent), /Could not load/);
  state = { ...state, phase: 'refreshing' };
  assert.equal(child.type(child.props).props.children.props.refreshing, true);
});
