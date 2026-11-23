/* global __dirname */
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const ts = require('typescript');

global.__DEV__ = false;

function load(file, dependencies = {}, imports = []) {
  const filename = path.resolve(__dirname, '..', file);
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX },
  }).outputText;
  const mod = new Module(filename, module);
  mod.filename = filename;
  mod.paths = module.paths;
  mod.require = (id) => { imports.push(id); return dependencies[id] ?? require(id); };
  mod._compile(compiled, filename);
  return mod.exports;
}

function findAll(node, predicate) {
  if (Array.isArray(node)) return node.flatMap((child) => findAll(child, predicate));
  if (!node || typeof node !== 'object') return [];
  return [...(predicate(node) ? [node] : []), ...findAll(node.props?.children, predicate)];
}

const native = { Text: 'Text', View: 'View', Pressable: 'Pressable', ActivityIndicator: 'ActivityIndicator', StyleSheet: { create: (value) => value } };
const ui = { Screen: 'Screen', Action: 'Action', styles: {} };
const model = load('lib/received-capsules.ts');
const preview = load('lib/received-preview.ts');
const content = load('components/received-capsules.tsx', { 'react-native': native, './ui': ui, '../lib/received-capsules': model }).ReceivedCapsulesContent;

const locked = {
  id: '00000000-0000-4000-8000-000000000251', sender_id: '00000000-0000-4000-8000-000000000253',
  created_at: '2025-06-02T14:00:00Z', unlock_at: '2025-06-03T14:00:00Z', status: 'locked',
};
const unlocked = { ...locked, id: '00000000-0000-4000-8000-000000000252', status: 'unlocked' };
const body = 'Synthetic message to reveal';
const inbox = { status: 'ok', items: [locked, unlocked] };
const success = { status: 'ok', message: { id: unlocked.id, body } };
const ready = { phase: 'ready', items: inbox.items, reveal: { phase: 'idle' } };
const actions = (tree) => findAll(tree, (node) => node.type === 'Action');
const status = (tree) => findAll(tree, (node) => node.props?.accessibilityLiveRegion === 'polite');

function pending() {
  let resolve;
  const promise = new Promise((complete) => { resolve = complete; });
  return { promise, resolve };
}

function controller(source) {
  const states = [];
  return { states, current: new model.ReceivedCapsulesController(source, (value) => states.push(value)) };
}

test('synthetic transport supplies only safe metadata and a separately requested unlocked message', async () => {
  const imports = [];
  const { createReceivedPreview } = load('lib/received-preview.ts', {}, imports);
  load('lib/received-capsules.ts', {}, imports);
  assert.deepEqual(imports, []);

  const source = createReceivedPreview('inbox');
  const signal = new AbortController().signal;
  const [listing, lockedResult, unlockedResult] = await Promise.all([
    source.load(signal), source.reveal(locked.id, signal), source.reveal(unlocked.id, signal),
  ]);
  assert.equal(listing.status, 'ok');
  assert.deepEqual(listing.items.map((item) => item.status), ['locked', 'unlocked']);
  for (const item of listing.items) {
    assert.deepEqual(Object.keys(item).sort(), ['created_at', 'id', 'sender_id', 'status', 'unlock_at']);
  }
  assert.equal(lockedResult.status, 'unavailable');
  assert.equal(unlockedResult.status, 'ok');
  assert.equal(unlockedResult.message.id, unlocked.id);
  assert.ok(!JSON.stringify(listing).includes(unlockedResult.message.body));
});

test('loading, empty, unavailable and retry have accessible generic messages', () => {
  const examples = [
    ['loading', 'Loading received capsules…', null],
    ['empty', 'No received capsules yet.', 'Refresh inbox'],
    ['unavailable', 'Received capsules are not available yet.', 'Refresh inbox'],
    ['error', 'Received capsules could not be loaded.', 'Retry'],
    ['auth', 'Your session could not be verified. Sign in again to view received capsules.', null],
  ];
  let refreshes = 0;
  for (const [phase, message, action] of examples) {
    const tree = content({ state: { phase }, onRefresh: () => { refreshes++; } });
    assert.deepEqual(status(tree).map((node) => node.props.children), [message]);
    assert.deepEqual(actions(tree).map((node) => node.props.title), action ? [action] : []);
    if (action) actions(tree)[0].props.onPress();
    const spinners = findAll(tree, (node) => node.type === 'ActivityIndicator');
    assert.equal(spinners.length, phase === 'loading' ? 1 : 0);
    if (spinners.length) assert.equal(spinners[0].props.importantForAccessibility, 'no');
  }
  assert.equal(refreshes, 3);
});

test('capsule cards display only safe status and offer one explicit unlocked action', () => {
  const revealed = [];
  const tree = content({ state: ready, onReveal: (id) => revealed.push(id) });
  const headings = findAll(tree, (node) => node.props?.accessibilityRole === 'header');
  assert.deepEqual(headings.map((node) => node.props.children), ['Locked capsule', 'Unlocked capsule']);
  const text = JSON.stringify(tree);
  assert.match(text, /last inbox refresh/);
  assert.match(text, new RegExp(locked.sender_id));
  assert.doesNotMatch(text, /Synthetic message|@example|sender_email/);
  assert.deepEqual(actions(tree).map((node) => node.props.title), ['Reveal message']);
  assert.deepEqual(revealed, []);
  actions(tree)[0].props.onPress();
  assert.deepEqual(revealed, [unlocked.id]);
});

test('a successful response displays the message separately from all list items', () => {
  const tree = content({ state: { ...ready, reveal: { phase: 'revealed', id: unlocked.id, body } }, onReveal() {} });
  const cards = findAll(tree, (node) => node.type === 'View');
  assert.equal(cards.length, 3);
  for (const card of cards.slice(0, 2)) assert.ok(!JSON.stringify(card).includes(body));
  const message = findAll(cards[2], (node) => node.type === 'Text' && node.props.children === body)[0];
  assert.ok(message);
  assert.equal(message.props.accessibilityLabel, undefined);
  assert.equal(status(tree)[0].props.children, 'Revealed message');
  assert.equal(actions(tree).length, 0);
});

test('metadata strips extra content and only a single explicit unlocked request can succeed', async () => {
  const response = pending();
  const requests = [];
  const source = {
    load: async () => ({ status: 'ok', items: [{ ...locked, body, sender_email: 'private@example.invalid' }, unlocked] }),
    reveal: (id) => { requests.push(id); return response.promise; },
  };
  const { current, states } = controller(source);
  await current.refresh();
  assert.deepEqual(states.at(-1), ready);
  await current.reveal(locked.id);
  await current.reveal('missing-id');
  assert.deepEqual(requests, []);

  const work = current.reveal(unlocked.id);
  await current.reveal(unlocked.id);
  assert.equal(states.at(-1).reveal.phase, 'revealing');
  const loading = content({ state: states.at(-1), onReveal() {} });
  assert.equal(status(loading)[0].props.children, 'Revealing message…');
  assert.equal(actions(loading).length, 0);
  assert.ok(!JSON.stringify(states).includes(body));
  assert.deepEqual(requests, [unlocked.id]);

  response.resolve(success);
  await work;
  assert.equal(states.at(-1).reveal.body, body);
  await current.reveal(unlocked.id);
  assert.deepEqual(requests, [unlocked.id]);
});

test('denial, ambiguity and a mismatched response expose no content and wait for refresh', async () => {
  const cases = [
    [{ status: 'unavailable' }, 'unavailable', /capsule is unavailable/],
    [{ status: 'uncertain' }, 'uncertain', /could not be confirmed/],
    [{ status: 'ok', message: { id: locked.id, body } }, 'uncertain', /could not be confirmed/],
    [{ throw: true }, 'uncertain', /could not be confirmed/],
  ];
  for (const [response, expected, message] of cases) {
    let requests = 0;
    const { current, states } = controller({ load: async () => inbox, async reveal() {
      requests++;
      if (response.throw) throw Error(body);
      return response;
    } });
    await current.refresh();
    await current.reveal(unlocked.id);
    assert.equal(states.at(-1).reveal.phase, expected);
    await current.reveal(unlocked.id);
    assert.equal(requests, 1);
    const tree = content({ state: states.at(-1), onRefresh() {}, onReveal() {} });
    assert.match(status(tree)[0].props.children, message);
    assert.deepEqual(actions(tree).map((node) => node.props.title), ['Refresh inbox']);
    assert.ok(!JSON.stringify(tree).includes(body));
    await current.refresh();
    assert.deepEqual(states.at(-1), ready);
  }
});

test('refresh cancels a pending reveal and clears a previously revealed message', async () => {
  const response = pending();
  let signal;
  let calls = 0;
  const { current, states } = controller({ load: async () => inbox, reveal(_id, requestSignal) {
    signal = requestSignal;
    return ++calls === 1 ? response.promise : Promise.resolve(success);
  } });
  await current.refresh();
  const work = current.reveal(unlocked.id);
  await current.refresh();
  assert.equal(signal.aborted, true);
  response.resolve(success);
  await work;
  assert.deepEqual(states.at(-1), ready);
  await current.reveal(unlocked.id);
  assert.equal(states.at(-1).reveal.body, body);
  await current.refresh();
  assert.deepEqual(states.at(-1), ready);
});

test('an interrupted session clears metadata and waits for a fresh controller', async () => {
  let loads = 0;
  const { current, states } = controller({ load: async () => { loads++; return inbox; }, reveal: async () => ({ status: 'auth' }) });
  await current.refresh();
  await current.reveal(unlocked.id);
  assert.deepEqual(states.at(-1), { phase: 'auth' });
  await current.refresh();
  await current.reveal(unlocked.id);
  assert.equal(loads, 1);
  assert.deepEqual(states.at(-1), { phase: 'auth' });
});

test('local empty and unavailable scenarios load and the load error recovers on retry', async () => {
  await Promise.all([['empty', 'empty'], ['unavailable', 'unavailable'], ['loadError', 'error']].map(async ([scenario, expected]) => {
    const { current, states } = controller(preview.createReceivedPreview(scenario));
    const work = current.refresh();
    assert.equal(states.at(-1).phase, 'loading');
    await work;
    assert.equal(states.at(-1).phase, expected);
    if (scenario === 'loadError') {
      await current.refresh();
      assert.equal(states.at(-1).phase, 'ready');
      assert.equal(states.at(-1).reveal.phase, 'idle');
    }
  }));
});

test('local reveal scenarios exercise the shared denial, uncertain and session interruption responses', async () => {
  await Promise.all([['revealDenied', 'unavailable'], ['revealUncertain', 'uncertain'], ['authInterrupted', 'auth']]
    .map(async ([scenario, expected]) => {
      const source = preview.createReceivedPreview(scenario);
      assert.deepEqual(await source.reveal(unlocked.id, new AbortController().signal), { status: expected });
    }));
});

test('refresh excludes a fixture withdrawn after the previous inbox snapshot', async () => {
  const { current, states } = controller(preview.createReceivedPreview('revealDenied'));
  await current.refresh();
  assert.equal(states.at(-1).items[1].id, unlocked.id);
  await current.reveal(unlocked.id);
  assert.equal(states.at(-1).reveal.phase, 'unavailable');
  await current.refresh();
  assert.deepEqual(states.at(-1).items.map((item) => item.id), [locked.id]);
  assert.equal(states.at(-1).reveal.phase, 'idle');
});

function screenHarness(getSession, enabled, source, onBack = () => {}) {
  let state = { phase: 'loading' };
  let scenario = 'inbox';
  let expanded = false;
  let focus;
  const ref = { current: null };
  const react = {
    useState(value) {
      if (typeof value === 'string') return [scenario, (next) => { scenario = next; }];
      if (typeof value === 'boolean') return [expanded, (next) => { expanded = next; }];
      return [state, (next) => { state = next; }];
    },
    useRef: () => ref,
    useCallback: (fn) => fn,
  };
  const screen = load('app/received-capsules.tsx', {
    react, 'react-native': native, 'expo-router': { router: { replace: onBack }, useFocusEffect: (fn) => { focus = fn; } },
    '../components/ui': ui, '../components/received-capsules': { ReceivedCapsulesContent: 'Content' },
    '../lib/auth': { useAuth: () => ({ session: getSession() }) }, '../lib/direct-feature': { directCapsulesEnabled: enabled },
    '../lib/received-capsules': model, '../lib/received-preview': { ...preview, createReceivedPreview: () => source },
  }).default;
  const localPreview = () => findAll(screen(), (node) => typeof node.type === 'function')[0];
  const previewTree = () => { const entry = localPreview(); return entry.type(entry.props); };
  const inboxEntry = () => findAll(previewTree(), (node) => typeof node.type === 'function')[0];
  const inboxTree = () => { const entry = inboxEntry(); return entry.type(entry.props); };
  return { screen, localPreview, previewTree, inboxEntry, inboxTree, focus: () => focus(), get state() { return state; } };
}

test('screen keeps the session and feature gates, and release remains unavailable', (t) => {
  t.mock.property(global, '__DEV__', false);
  let session = { user: { id: 'synthetic' } };
  const paths = [];
  assert.equal(screenHarness(() => session, false).screen(), null);
  const harness = screenHarness(() => session, true, undefined, (path) => paths.push(path));
  const tree = harness.screen();
  assert.equal(tree.props.topAligned, true);
  assert.deepEqual(findAll(tree, (node) => node.type === 'Content')[0].props.state, { phase: 'unavailable' });
  assert.equal(harness.localPreview(), undefined);
  actions(tree).find((node) => node.props.title === 'Back to home').props.onPress();
  assert.deepEqual(paths, ['/home']);
  session = null;
  assert.equal(harness.screen(), null);
});

test('development preview scenario choices are accessible and remount the inbox', (t) => {
  t.mock.property(global, '__DEV__', true);
  const session = { user: { id: 'synthetic' } };
  const harness = screenHarness(() => session, true);
  assert.equal(harness.inboxEntry().key, 'inbox');
  const toggle = findAll(harness.previewTree(), (node) => node.type === 'Pressable')[0];
  assert.equal(toggle.props.accessibilityState.expanded, false);
  toggle.props.onPress();
  const [, ...options] = findAll(harness.previewTree(), (node) => node.type === 'Pressable');
  assert.equal(options[0].props.accessibilityState.selected, true);
  assert.ok(options.every((choice) => choice.props.accessibilityRole === 'button'));
  options[1].props.onPress();
  assert.equal(harness.inboxEntry().key, 'empty');
});

test('blur during reveal discards late success and reauthentication remounts the preview', async (t) => {
  t.mock.property(global, '__DEV__', true);
  const response = pending();
  let signal;
  let session = { user: { id: 'synthetic' } };
  const harness = screenHarness(() => session, true, { load: async () => inbox, reveal(_id, requestSignal) {
    signal = requestSignal;
    return response.promise;
  } });
  const firstKey = harness.localPreview().key;
  harness.inboxTree();
  const blur = harness.focus();
  await Promise.resolve();
  harness.inboxTree().props.onReveal(unlocked.id);
  assert.equal(harness.state.reveal.phase, 'revealing');
  blur();
  assert.equal(signal.aborted, true);
  response.resolve(success);
  await Promise.resolve();
  assert.deepEqual(harness.state, { phase: 'loading' });

  session = { user: { id: 'synthetic' } };
  assert.notEqual(harness.localPreview().key, firstKey);
  harness.inboxTree();
  const leave = harness.focus();
  await Promise.resolve();
  assert.deepEqual(harness.state, ready);
  leave();
  session = null;
  assert.equal(harness.screen(), null);
});
