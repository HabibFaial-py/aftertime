// This parser-blocking script runs before the document body. It is the only
// script in the local invitation response and has no external dependencies.
export const handoffScript = String.raw`(() => {
  const path = window.location.pathname;
  const capsule = /^\/invite\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/.exec(path);
  const safePath = capsule ? path : "/invite";

  function scrubLocation() {
    try {
      window.history.replaceState(null, "", safePath);
      return true;
    } catch {
      try { window.location.replace(safePath); } catch { /* Keep the invitation unavailable. */ }
      return false;
    }
  }

  function readInvitation() {
    const fragment = window.location.hash;
    const canonical = window.location.href === window.location.origin + path + fragment;
    if (!scrubLocation() || !canonical || !capsule || fragment.length !== 44) return null;
    const value = fragment.slice(1);
    return /^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/.test(value) ? value : null;
  }

  const reopenPage = path === "/invite" && !window.location.hash && !window.location.search;
  let secret = readInvitation();
  let state = secret ? "authentication" : reopenPage ? "reopen" : "unavailable";
  let render = () => {};

  function discard(nextState) {
    secret = null;
    state = nextState;
    render();
  }

  function invalidateNavigation() {
    discard("reopen");
    scrubLocation();
  }

  window.addEventListener("pagehide", () => discard("reopen"));
  window.addEventListener("pageshow", (event) => {
    if (event.persisted) invalidateNavigation();
  });
  window.addEventListener("popstate", invalidateNavigation);
  window.addEventListener("hashchange", invalidateNavigation);

  // This fake accepts only synthetic fixture input. Nothing leaves the browser.
  function fakeClaim(capsuleId, value) {
    if (value !== "A".repeat(43)) return "unavailable";
    switch (capsuleId) {
      case "00000000-0000-4000-8000-000000000201": return "claimed";
      case "00000000-0000-4000-8000-000000000202": return "expired";
      case "00000000-0000-4000-8000-000000000203": return "already_claimed";
      case "00000000-0000-4000-8000-000000000204": return "unknown";
      default: return "unavailable";
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    const message = document.getElementById("invitation-status");
    const authentication = document.getElementById("authentication-actions");
    const claim = document.getElementById("claim-invitation");
    const messages = {
      authentication: "Sign in is required to claim this invitation.",
      ready: "Test session ready. Confirm that you want to claim this invitation.",
      reopen: "Reopen the original invitation in a new tab after signing in.",
      unavailable: "This invitation is unavailable.",
      claimed: "Invitation claimed in this local test.",
      unknown: "The claim status could not be confirmed.",
    };

    render = () => {
      message.textContent = messages[state];
      authentication.hidden = state !== "authentication";
      claim.hidden = state !== "ready";
    };

    document.getElementById("test-session").addEventListener("click", () => {
      if (state !== "authentication" || !secret) return;
      state = "ready";
      render();
      claim.focus();
    });

    document.getElementById("interrupt-sign-in").addEventListener("click", () => {
      if (state !== "authentication" || !secret) return;
      discard("reopen");
      window.location.replace("/invite");
    });

    claim.addEventListener("click", () => {
      if (state !== "ready" || !secret || !capsule) return;
      const attempt = secret;
      secret = null;
      let outcome;
      try {
        outcome = fakeClaim(capsule[1], attempt);
      } catch {
        outcome = "unknown";
      }
      const nextState = outcome === "claimed" || outcome === "unknown" ? outcome : "unavailable";
      discard(nextState);
      message.focus();
    });

    render();
  }, { once: true });
})();`;
