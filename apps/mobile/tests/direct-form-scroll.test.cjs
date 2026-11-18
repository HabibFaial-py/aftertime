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

test('focused fields and requested feedback scroll without keeping stale callbacks', () => {
  const oldRequest = global.requestAnimationFrame; const oldCancel = global.cancelAnimationFrame;
  let nextFrame = 0; const frames = new Map(); const listeners = {}; const removed = []; const calls = [];
  global.requestAnimationFrame = (callback) => { const id = ++nextFrame; frames.set(id, callback); return id; };
  global.cancelAnimationFrame = (id) => frames.delete(id);
  let visible = false; let cleanup;
  const keyboard = { isVisible: () => visible, addListener(name, callback) {
    listeners[name] = callback; return { remove() { removed.push(name); delete listeners[name]; } };
  } };
  const react = { useRef: (value) => ({ current: value }), useEffect: (callback) => { cleanup = callback(); } };
  try {
    const { useDirectFormScroll } = load('components/use-direct-form-scroll.ts', { react, 'react-native': { Keyboard: keyboard } });
    const form = useDirectFormScroll();
    form.scrollRef.current = {
      scrollResponderScrollNativeHandleToKeyboard: (...args) => calls.push(['focus', ...args]),
      scrollTo: (options) => calls.push(['feedback', options]),
    };
    function flush() { const pending = [...frames.values()]; frames.clear(); pending.forEach((fn) => fn()); }
    const event = (target) => ({ nativeEvent: { target } });
    form.onFocus(event(1)); flush(); assert.deepEqual(calls, []);
    visible = true; listeners.keyboardDidShow(); flush(); assert.deepEqual(calls, [['focus', 1, 24, true]]);
    form.onFocus(event(2)); flush(); assert.deepEqual(calls.at(-1), ['focus', 2, 24, true]);
    form.onFocus(event(3)); form.onBlur(event(3)); flush(); assert.equal(calls.length, 2);
    form.onFocus(event(4)); form.onFeedbackLayout({ nativeEvent: { layout: { y: 240 } } });
    form.showFeedback(); listeners.keyboardDidShow(); listeners.keyboardDidHide(); flush();
    assert.deepEqual(calls.at(-1), ['feedback', { y: 216, animated: true }]);
    listeners.keyboardDidShow(); flush(); assert.equal(calls.length, 3);
    form.onFocus(event(5)); listeners.keyboardDidHide(); flush(); assert.equal(calls.length, 3);
    form.onFocus(event(6)); cleanup(); flush(); assert.equal(calls.length, 3);
    assert.deepEqual(removed.sort(), ['keyboardDidHide', 'keyboardDidShow']);
  } finally { global.requestAnimationFrame = oldRequest; global.cancelAnimationFrame = oldCancel; }
});

test('shared screen keeps its safe area, keyboard avoidance and handled taps', () => {
  const native = { KeyboardAvoidingView: 'KeyboardAvoidingView', ScrollView: 'ScrollView', Platform: { OS: 'android' },
    Pressable: 'Pressable', Text: 'Text', StyleSheet: { create: (styles) => styles } };
  const { Screen, styles } = load('components/ui.tsx', { 'react-native': native, 'react-native-safe-area-context': { SafeAreaView: 'SafeAreaView' } });
  const scrollRef = {};
  const tree = Screen({ children: 'content', scrollRef, topAligned: true });
  assert.equal(tree.type, 'SafeAreaView');
  const avoiding = tree.props.children;
  assert.equal(avoiding.type, 'KeyboardAvoidingView'); assert.equal(avoiding.props.behavior, 'height');
  const scroll = avoiding.props.children;
  assert.equal(scroll.type, 'ScrollView'); assert.equal(scroll.props.ref, scrollRef);
  assert.equal(scroll.props.keyboardShouldPersistTaps, 'handled');
  assert.deepEqual(scroll.props.contentContainerStyle, [styles.content, styles.topAligned]);
  assert.ok(styles.button.minHeight >= 48);
});
