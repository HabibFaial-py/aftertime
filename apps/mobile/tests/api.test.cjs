/* global __dirname */
const { test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const ts = require('typescript');

// Compile the actual TypeScript modules in memory and replace only Supabase.
global.__DEV__ = true;
process.env.EXPO_PUBLIC_API_BASE_URL = 'http://127.0.0.1:8001';
let session;
const mockSupabase = { auth: { getSession: async () => ({ data: { session }, error: null }) } };
function load(name, dependencies) {
  const filename = path.resolve(__dirname, '../lib', name + '.ts');
  const source = fs.readFileSync(filename, 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
  const mod = new Module(filename, module);
  mod.filename = filename;
  mod.paths = module.paths;
  mod.require = (id) => dependencies[id] ?? require(id);
  mod._compile(compiled, filename);
  return mod.exports;
}
const api = load('api', { './supabase': { supabase: mockSupabase } });
const capsules = load('capsules', { './api': api });
const id = 'e3216d4c-9b6e-4f8b-8493-7e3a3ac7da80';
const time = '2026-11-14T10:00:00Z';
const signal = () => new AbortController().signal;
const response = (status, body) => ({ status, json: async () => body });
beforeEach(() => { session = { user: { id }, access_token: 'mock-token', expires_at: Date.now() / 1000 + 300 }; });

test('auth/me retains identity check and authenticated request options', async () => {
  global.fetch = async (url, options) => {
    assert.equal(url, 'http://127.0.0.1:8001/v1/auth/me');
    assert.equal(options.headers.Authorization, 'Bearer mock-token');
    assert.equal(options.redirect, 'error');
    return response(200, { id });
  };
  assert.deepEqual(await api.getAuthenticatedUser(id, signal()), { id });
  global.fetch = async () => response(200, { id: 'other' });
  await assert.rejects(api.getAuthenticatedUser(id, signal()), { kind: 'response' });
});

test('changed and expired sessions do not send requests', async () => {
  let calls = 0;
  global.fetch = async () => { calls++; return response(200, { id }); };
  session.user.id = 'other';
  await assert.rejects(api.getAuthenticatedUser(id, signal()), { kind: 'session' });
  session.user.id = id; session.expires_at = Date.now() / 1000 - 1;
  await assert.rejects(api.getAuthenticatedUser(id, signal()), { kind: 'session' });
  assert.equal(calls, 0);
});

test('status, malformed JSON, no-content, network and timeout failures are safe', async () => {
  for (const status of [401, 403, 404, 422, 503]) {
    global.fetch = async () => response(status, { private: 'never exposed' });
    await assert.rejects(api.getAuthenticatedUser(id, signal()), { kind: status === 401 || status === 403 ? 'unauthorized' : 'response', status });
  }
  global.fetch = async () => ({ status: 200, json: async () => { throw new Error('private'); } });
  await assert.rejects(api.getAuthenticatedUser(id, signal()), { kind: 'response' });
  global.fetch = async () => response(204);
  assert.equal(await api.authenticatedRequest({ expectedUserId: id, signal: signal(), path: '/v1/test', expectedStatuses: [204], parse: (v) => v }), undefined);
  await assert.rejects(api.getAuthenticatedUser(id, signal()), { kind: 'response' });
  global.fetch = async () => { throw new Error('private'); };
  await assert.rejects(api.getAuthenticatedUser(id, signal()), { kind: 'network' });
  global.fetch = () => new Promise(() => {});
  await assert.rejects(api.getAuthenticatedUser(id, signal(), 5), { kind: 'timeout' });
});

test('abort interrupts pending session and fetch', async () => {
  const original = mockSupabase.auth.getSession;
  mockSupabase.auth.getSession = () => new Promise(() => {});
  const controller = new AbortController();
  const pending = api.getAuthenticatedUser(id, controller.signal);
  controller.abort();
  await assert.rejects(pending, { kind: 'cancelled' });
  mockSupabase.auth.getSession = original;
  global.fetch = () => new Promise(() => {});
  const second = new AbortController();
  const fetching = api.getAuthenticatedUser(id, second.signal);
  await Promise.resolve(); await Promise.resolve();
  second.abort();
  await assert.rejects(fetching, { kind: 'cancelled' });
});

test('create sends only specified fields once, with expected status', async () => {
  let calls = 0;
  global.fetch = async (_url, options) => {
    calls++;
    assert.equal(options.method, 'POST');
    assert.equal(options.headers['Content-Type'], 'application/json');
    assert.deepEqual(JSON.parse(options.body), { title: 'title', body: 'private', unlock_at: time });
    return response(201, { id, title: 'title', unlock_at: time, created_at: time });
  };
  await capsules.createCapsule(id, signal(), { title: 'title', body: 'private', unlock_at: time, extra: 'ignored' });
  assert.equal(calls, 1);
  global.fetch = async () => { calls++; throw new Error('network'); };
  await assert.rejects(capsules.createCapsule(id, signal(), { title: 'title', body: 'private', unlock_at: time }), { kind: 'network' });
  assert.equal(calls, 2);
  global.fetch = async () => { calls++; return response(200, { id }); };
  await assert.rejects(capsules.createCapsule(id, signal(), { title: 'title', body: 'private', unlock_at: time }), { kind: 'response', status: 200 });
  assert.equal(calls, 3);
  global.fetch = () => { calls++; return new Promise(() => {}); };
  await assert.rejects(api.authenticatedRequest({ expectedUserId: id, signal: signal(), path: '/v1/capsules', method: 'POST', body: {}, expectedStatuses: [201], parse: (v) => v, timeoutMs: 5 }), { kind: 'timeout' });
  assert.equal(calls, 4);
});

test('list validates metadata, pagination and refuses private fields', async () => {
  global.fetch = async (url) => { assert.match(url, /limit=1&offset=2$/); return response(200, [{ id, title: 'title', unlock_at: time, created_at: time, status: 'locked' }]); };
  assert.equal((await capsules.listCapsules(id, signal(), 1, 2))[0].status, 'locked');
  global.fetch = async () => response(200, [{ id, title: 'title', unlock_at: time, created_at: time, status: 'locked', body: 'private' }]);
  await assert.rejects(capsules.listCapsules(id, signal()), { kind: 'response' });
  assert.throws(() => capsules.listCapsules(id, signal(), 51), { kind: 'response' });
});

test('reveal is explicit, validates ID and does not persist private content', async () => {
  let calls = 0;
  global.fetch = async (url) => { calls++; assert.match(url, /\/reveal$/); return response(200, { id, body: 'private' }); };
  assert.equal(calls, 0);
  assert.deepEqual(await capsules.revealCapsule(id, signal(), id), { id, body: 'private' });
  global.fetch = async () => response(200, { id: 'not-a-uuid', body: 'private' });
  await assert.rejects(capsules.revealCapsule(id, signal(), id), { kind: 'response' });
  assert.throws(() => capsules.revealCapsule(id, signal(), '../private'), { kind: 'response' });
});

test('cancellation sends no body and validates response', async () => {
  global.fetch = async (_url, options) => { assert.equal(options.method, 'POST'); assert.equal(options.body, undefined); return response(200, { id, cancelled_at: time }); };
  assert.deepEqual(await capsules.cancelCapsule(id, signal(), id), { id, cancelled_at: time });
});
