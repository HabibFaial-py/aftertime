import assert from "node:assert/strict";
import { test } from "node:test";
import { runInNewContext } from "node:vm";
import { handoffScript } from "../app/invite/handoff-script.mjs";

const origin = "http://127.0.0.1:3100";
const secret = "A".repeat(43);
const fixturePath = (suffix = "201") => `/invite/00000000-0000-4000-8000-000000000${suffix}`;

function open(path, { failReplaceState = false, script = handoffScript } = {}) {
  let url = new URL(path, origin);
  const history = [];
  const redirects = [];
  const accesses = [];
  const elements = new Map();
  const pageEvents = new Map();
  const documentEvents = new Map();
  const location = {
    get href() { return url.href; }, get origin() { return url.origin; },
    get pathname() { return url.pathname; }, get search() { return url.search; },
    get hash() { return url.hash; },
    replace(destination) { redirects.push(destination); url = new URL(destination, url); },
  };
  const window = {
    location,
    history: { replaceState(state, title, destination) {
      if (failReplaceState) throw new Error("History unavailable");
      history.push({ state, title, destination });
      url = new URL(destination, url);
    } },
    addEventListener(event, handler) { pageEvents.set(event, handler); },
    get localStorage() { accesses.push("localStorage"); },
    get sessionStorage() { accesses.push("sessionStorage"); },
  };
  const document = {
    addEventListener(event, handler) { documentEvents.set(event, handler); },
    getElementById(id) {
      const element = {
        textContent: "", hidden: true,
        addEventListener(event, handler) { element[event] = handler; },
        focus() {},
      };
      elements.set(id, element);
      return element;
    },
    get cookie() { accesses.push("cookie"); },
    set cookie(_) { accesses.push("cookie"); },
  };

  runInNewContext(script, { window, document, fetch() { accesses.push("network"); } });
  return {
    get url() { return url; }, history, redirects, accesses, elements,
    mount() { documentEvents.get("DOMContentLoaded")(); },
    emit(event, details) { pageEvents.get(event)(details); },
    setLocation(pathname) { url = new URL(pathname, url); },
    click(id) { elements.get(id).click(); },
    get message() { return elements.get("invitation-status").textContent; },
    get claimVisible() { return !elements.get("claim-invitation").hidden; },
  };
}

test("scrubs the valid fragment before mounting with empty browser history state", () => {
  const page = open(`${fixturePath()}#${secret}`);
  assert.equal(page.elements.size, 0);
  assert.equal(page.url.href, origin + fixturePath());
  assert.deepEqual(page.history, [{ state: null, title: "", destination: fixturePath() }]);
  page.mount();
  assert.match(page.message, /Sign in is required/);
  assert.equal(page.claimVisible, false);
});

test("opening and simulated authentication leave claiming to the explicit action", () => {
  const page = open(`${fixturePath()}#${secret}`);
  page.mount();
  page.click("claim-invitation");
  assert.match(page.message, /Sign in is required/);
  page.click("test-session");
  assert.match(page.message, /Confirm that you want to claim/);
  assert.equal(page.claimVisible, true);
  page.click("claim-invitation");
  assert.equal(page.message, "Invitation claimed in this local test.");
  assert.equal(page.claimVisible, false);
  page.click("claim-invitation");
  assert.equal(page.message, "Invitation claimed in this local test.");
});

for (const [kind, path] of [
  ["query parameter", `${fixturePath()}?extra=x#${secret}`],
  ["empty query", `${fixturePath()}?#${secret}`],
  ["invalid UUID", `/invite/not-a-uuid#${secret}`],
  ["short fragment", `${fixturePath()}#${secret.slice(1)}`],
  ["noncanonical pad bits", `${fixturePath()}#${secret.slice(1)}B`],
  ["explicit padding", `${fixturePath()}#${secret}=`],
  ["encoded fragment", `${fixturePath()}#%41${secret.slice(1)}`],
  ["oversized fragment", `${fixturePath()}#${secret.repeat(100)}`],
]) {
  test(`scrubs and denies malformed input with ${kind}`, () => {
    const page = open(path);
    assert.equal(page.url.hash + page.url.search, "");
    page.mount();
    assert.equal(page.message, "This invitation is unavailable.");
    assert.equal(page.claimVisible, false);
  });
}

test("authentication interruption abandons the secret and navigates without it", () => {
  const page = open(`${fixturePath()}#${secret}`);
  page.mount();
  page.click("interrupt-sign-in");
  assert.deepEqual(page.redirects, ["/invite"]);
  assert.match(page.message, /Reopen the original invitation/);
  page.click("test-session");
  assert.equal(page.claimVisible, false);
});

test("refresh has no fragment to restore and back navigation clears the prior session", () => {
  const page = open(`${fixturePath()}#${secret}`);
  page.mount();
  page.click("test-session");

  const refreshed = open(page.url.pathname);
  refreshed.mount();
  assert.equal(refreshed.claimVisible, false);
  assert.equal(refreshed.message, "This invitation is unavailable.");

  page.emit("pagehide", { persisted: true });
  page.emit("pageshow", { persisted: true });
  page.setLocation(`${fixturePath()}#${secret}`);
  page.emit("popstate");
  assert.equal(page.url.hash, "");
  assert.match(page.message, /Reopen the original invitation/);
  assert.equal(page.claimVisible, false);
});

test("a same-document fragment change is scrubbed and cannot revive a session", () => {
  const page = open(`${fixturePath()}#${secret}`);
  page.mount();
  page.setLocation(`${fixturePath()}#${secret}`);
  page.emit("hashchange");
  assert.equal(page.url.hash, "");
  page.click("test-session");
  assert.equal(page.claimVisible, false);
});

test("the handoff never uses storage, cookies or network calls or renders the secret", () => {
  const page = open(`${fixturePath()}#${secret}`);
  page.mount();
  page.click("test-session");
  page.click("claim-invitation");
  assert.deepEqual(page.accesses, []);
  assert.ok([...page.elements.values()].every(({ textContent }) => !textContent.includes(secret)));
  assert.ok(!JSON.stringify(page.history).includes(secret));
});

test("expired, already-claimed, unavailable and wrong secrets all use a generic denial", () => {
  for (const path of [
    `${fixturePath("202")}#${secret}`, `${fixturePath("203")}#${secret}`,
    `${fixturePath("205")}#${secret}`, `${fixturePath()}#${"Q".repeat(43)}`,
  ]) {
    const page = open(path);
    page.mount();
    page.click("test-session");
    page.click("claim-invitation");
    assert.equal(page.message, "This invitation is unavailable.");
    assert.equal(page.claimVisible, false);
  }
});

test("uncertain and exceptional fake results are generic and consume the page-held secret", () => {
  for (const script of [handoffScript, handoffScript.replace('return "unknown";', 'throw Error(value);')]) {
    const page = open(`${fixturePath("204")}#${secret}`, { script });
    page.mount();
    page.click("test-session");
    page.click("claim-invitation");
    assert.equal(page.message, "The claim status could not be confirmed.");
    assert.equal(page.claimVisible, false);
  }
});

test("a failed history replacement abandons the secret and replaces only the clean URL", () => {
  const page = open(`${fixturePath()}#${secret}`, { failReplaceState: true });
  assert.deepEqual(page.redirects, [fixturePath()]);
  page.mount();
  assert.equal(page.message, "This invitation is unavailable.");
  assert.equal(page.claimVisible, false);
});
