/* global __dirname */
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const ts = require('typescript');

function load(file, dependencies = {}) {
  const filename = path.resolve(__dirname, '..', file);
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX },
  }).outputText;
  const mod = new Module(filename, module);
  mod.filename = filename; mod.paths = module.paths;
  mod.require = (id) => dependencies[id] ?? require(id);
  mod._compile(output, filename);
  return mod.exports;
}

function findAll(node, predicate) {
  if (!node || typeof node !== 'object') return [];
  const children = node.props?.children;
  return [...(predicate(node) ? [node] : []),
    ...(Array.isArray(children) ? children : [children]).flatMap((child) => findAll(child, predicate))];
}

const ui = { Screen: 'Screen', Action: 'Action', styles: { title: {}, text: {}, label: {}, input: {}, error: {} } };
const native = { Text: 'Text', TextInput: 'TextInput', ActivityIndicator: 'ActivityIndicator' };

test('flag defaults off and only exact true enables it', () => {
  const previous = process.env.EXPO_PUBLIC_DIRECT_CAPSULES_ENABLED;
  try {
    for (const value of [undefined, '', 'false', 'TRUE', '1']) {
      if (value === undefined) delete process.env.EXPO_PUBLIC_DIRECT_CAPSULES_ENABLED;
      else process.env.EXPO_PUBLIC_DIRECT_CAPSULES_ENABLED = value;
      assert.equal(load('lib/direct-feature.ts').directCapsulesEnabled, false);
    }
    process.env.EXPO_PUBLIC_DIRECT_CAPSULES_ENABLED = 'true';
    assert.equal(load('lib/direct-feature.ts').directCapsulesEnabled, true);
  } finally {
    if (previous === undefined) delete process.env.EXPO_PUBLIC_DIRECT_CAPSULES_ENABLED;
    else process.env.EXPO_PUBLIC_DIRECT_CAPSULES_ENABLED = previous;
  }
});

test('direct routes require both the flag and an authenticated session', () => {
  function stack() {} stack.Protected = 'Protected'; stack.Screen = 'StackScreen';
  for (const enabled of [false, true]) for (const signedIn of [false, true]) {
    const layout = load('app/_layout.tsx', {
      'expo-router': { Stack: stack }, 'expo-status-bar': { StatusBar: 'StatusBar' },
      'react-native-safe-area-context': { SafeAreaProvider: 'SafeAreaProvider' }, 'react-native': native,
      '../lib/auth': { AuthProvider: 'AuthProvider', useAuth: () => ({ session: signedIn ? {} : null, loading: false }) },
      '../components/ui': ui, '../lib/direct-feature': { directCapsulesEnabled: enabled },
    }).default;
    const provider = findAll(layout(), (element) => element.type === 'AuthProvider')[0];
    const tree = provider.props.children.type();
    const directGuard = findAll(tree, (element) => element.type === 'Protected' &&
      findAll(element, (child) => child.type === 'StackScreen' && child.props.name === 'send-to-someone').length)[0];
    assert.equal(directGuard.props.guard, enabled && signedIn);
    assert.equal(findAll(directGuard, (child) => child.type === 'StackScreen' && child.props.name === 'received-capsules').length, 1);
    assert.equal(findAll(tree, (child) => child.type === 'StackScreen' && child.props.name === 'create-capsule').length, 1);
  }
});

test('home exposes direct links only when enabled and keeps self navigation', () => {
  for (const enabled of [false, true]) {
    const paths = [];
    const home = load('app/home.tsx', {
      react: { useEffect: () => {}, useRef: () => ({ current: false }), useState: (value) => [value, () => {}] },
      'react-native': native, 'expo-router': { router: { push: (path) => paths.push(path) } },
      '../lib/auth': { useAuth: () => ({ session: { user: { id: 'synthetic' } } }) },
      '../lib/supabase': {}, '../lib/api': {}, '../components/ui': ui,
      '../lib/direct-feature': { directCapsulesEnabled: enabled },
    }).default;
    const actions = findAll(home(), (element) => element.type === 'Action');
    actions.find((element) => element.props.title === 'View capsules').props.onPress();
    assert.deepEqual(paths, ['/capsules']);
    for (const [title, destination] of [['Send to Someone', '/send-to-someone'], ['Received Capsules', '/received-capsules']]) {
      const action = actions.find((element) => element.props.title === title);
      assert.equal(Boolean(action), enabled);
      if (action) { action.props.onPress(); assert.equal(paths.at(-1), destination); }
    }
  }
});

test('direct draft validates required fields and API text limits', () => {
  class ApiError extends Error {}
  const self = load('lib/capsule-create.ts', { './api': { ApiError }, './capsules': {} });
  const unlock = load('lib/direct-unlock-time.ts', { './capsule-create': self });
  const direct = load('lib/direct-draft.ts', { './direct-unlock-time': unlock });
  const validateDirectDraft = (draft, now) => {
    const result = direct.validateDirectDraft(draft, now);
    return result.ok ? '' : result.error;
  };
  const now = Date.now();
  const future = new Date(now + 2 * 86400000);
  const pad = (n) => String(n).padStart(2, '0');
  const draft = { recipient: 'person@example.invalid', title: 'A title', body: 'hello',
    date: `${future.getFullYear()}-${pad(future.getMonth() + 1)}-${pad(future.getDate())}`,
    time: `${pad(future.getHours())}:${pad(future.getMinutes())}` };
  assert.equal(validateDirectDraft(draft, now), '');
  assert.match(validateDirectDraft({ ...draft, recipient: 'not an email' }, now), /email/);
  assert.equal(validateDirectDraft({ ...draft, recipient: `${'a'.repeat(252)}@b` }, now), '');
  assert.equal(validateDirectDraft({ ...draft, recipient: `${'😀'.repeat(252)}@b` }, now), '');
  assert.match(validateDirectDraft({ ...draft, recipient: `${'a'.repeat(253)}@b` }, now), /email/);
  assert.match(validateDirectDraft({ ...draft, recipient: `${' '.repeat(251)}a@b ` }, now), /email/);
  assert.match(validateDirectDraft({ ...draft, recipient: 'a\0@b' }, now), /email/);
  assert.match(validateDirectDraft({ ...draft, recipient: 'a\ud800@b' }, now), /email/);
  assert.match(validateDirectDraft({ ...draft, title: ' \t' }, now), /title/);
  assert.match(validateDirectDraft({ ...draft, title: 'title\0' }, now), /invalid characters/);
  assert.match(validateDirectDraft({ ...draft, title: 'title\ud800' }, now), /invalid characters/);
  assert.equal(validateDirectDraft({ ...draft, title: 'a'.repeat(5000) }, now), '');
  assert.match(validateDirectDraft({ ...draft, body: ' ' }, now), /message/);
  assert.match(validateDirectDraft({ ...draft, body: 'message\0' }, now), /invalid characters/);
  assert.match(validateDirectDraft({ ...draft, body: 'message\udfff' }, now), /invalid characters/);
  assert.equal(validateDirectDraft({ ...draft, body: '😀'.repeat(2000) }, now), '');
  assert.match(validateDirectDraft({ ...draft, body: '😀'.repeat(2001) }, now), /2,000/);
  assert.match(validateDirectDraft({ ...draft, body: 'a'.repeat(2001) }, now), /2,000/);
  assert.match(validateDirectDraft({ ...draft, date: '2026-02-30' }, now), /date and time/);
  assert.match(validateDirectDraft({ ...draft, date: '2000-01-01' }, now), /future/);
  const tooLate = new Date(now + 91 * 86400000);
  assert.match(validateDirectDraft({ ...draft, date: `${tooLate.getFullYear()}-${pad(tooLate.getMonth() + 1)}-${pad(tooLate.getDate())}` }, now), /90 days/);
});

test('send screen checks input without submitting and clears feedback on edit', () => {
  const values = []; let cursor = 0; let destination; let checked;
  const react = { useState(initial) { const index = cursor++; if (!(index in values)) values[index] = initial;
    return [values[index], (value) => { values[index] = value; }]; } };
  const screen = load('app/send-to-someone.tsx', { react, 'react-native': native, '../components/ui': ui,
    'expo-router': { router: { replace: (path) => { destination = path; } } },
    '../lib/direct-draft': { validateDirectDraft: (draft) => { checked = draft; return draft.recipient ?
      { ok: true, utc: '2026-12-31T19:00:00.000Z', offset: 'UTC+05:00' } :
      { ok: false, error: 'Enter a valid recipient email address.' }; } },
  }).default;
  function render() { cursor = 0; return screen(); }
  function action(tree, title) { return findAll(tree, (element) => element.type === 'Action' && element.props.title === title)[0]; }
  action(render(), 'Check details').props.onPress();
  assert.match(JSON.stringify(render()), /valid recipient email/);
  findAll(render(), (element) => element.type === 'TextInput' && element.props.accessibilityLabel === 'Recipient email')[0].props.onChangeText('person@example.invalid');
  findAll(render(), (element) => element.type === 'TextInput' && element.props.accessibilityLabel === 'Title')[0].props.onChangeText('A title');
  findAll(render(), (element) => element.type === 'TextInput' && element.props.accessibilityLabel === 'Local reveal date, year month day')[0].props.onChangeText('2027-01-01');
  findAll(render(), (element) => element.type === 'TextInput' && element.props.accessibilityLabel === 'Local reveal time, 24-hour hours and minutes')[0].props.onChangeText('00:00');
  assert.doesNotMatch(JSON.stringify(render()), /valid recipient email/);
  action(render(), 'Check details').props.onPress();
  assert.equal(checked.title, 'A title');
  assert.match(JSON.stringify(render()), /Nothing has been sent/);
  for (const text of ['Confirm reveal time', 'Local date:', '2027-01-01', 'Local time:', '00:00', 'Timezone:', 'UTC+05:00', 'UTC equivalent:', '2026-12-31T19:00:00.000Z']) {
    assert.ok(JSON.stringify(render()).includes(text), `missing ${text}`);
  }
  findAll(render(), (element) => element.type === 'TextInput' && element.props.accessibilityLabel === 'Local reveal time, 24-hour hours and minutes')[0].props.onChangeText('00:01');
  assert.doesNotMatch(JSON.stringify(render()), /UTC equivalent/);
  assert.equal(findAll(render(), (element) => element.type === 'Action' && /send|seal/i.test(element.props.title)).length, 0);
  action(render(), 'Back to home').props.onPress(); assert.equal(destination, '/home');
});

test('received screen defaults to unavailable and supports loading, error and empty presentation', () => {
  const content = load('components/received-capsules.tsx', { 'react-native': native, './ui': ui }).ReceivedCapsulesContent;
  for (const [state, expected] of [['unavailable', 'not available yet'], ['loading', 'Loading received capsules'],
    ['error', 'could not be loaded'], ['empty', 'no received capsules']]) {
    const tree = content({ state }); const text = JSON.stringify(tree);
    assert.match(text, new RegExp(expected)); assert.match(text, /Pending/); assert.match(text, /Claimed/);
  }
  const screen = load('app/received-capsules.tsx', { 'react-native': native, '../components/ui': ui,
    'expo-router': { router: { replace: () => {} } }, '../components/received-capsules': { ReceivedCapsulesContent: content },
  }).default;
  assert.equal(findAll(screen(), (element) => element.type === content)[0].props.state, 'unavailable');
});
