import { randomBytes } from "node:crypto";
import { handoffScript } from "../handoff-script.mjs";

export const dynamic = "force-dynamic";

const privacyHeaders = {
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Robots-Tag": "noindex, nofollow",
};

export function GET(request: Request) {
  const host = request.headers.get("host") ?? "";
  if (process.env.NODE_ENV !== "development" || process.env.AFTERTIME_LOCAL_WEB_INVITE !== "1"
      || !/^127\.0\.0\.1(?::[1-9][0-9]{0,4})?$/.test(host)) {
    return new Response("Not found", { status: 404, headers: privacyHeaders });
  }

  const nonce = randomBytes(18).toString("base64");
  const policy = [
    "default-src 'none'", `script-src 'nonce-${nonce}'`, "script-src-attr 'none'",
    `style-src 'nonce-${nonce}'`, "connect-src 'none'", "base-uri 'none'",
    "form-action 'none'", "frame-ancestors 'none'",
  ].join("; ");

  return new Response(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <script nonce="${nonce}">${handoffScript}</script>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Capsule invitation | AfterTime</title>
  <style nonce="${nonce}">
    * { box-sizing: border-box; }
    body { margin: 0; background: #fbf6ef; color: #332a25; font: 1rem/1.55 Arial, Helvetica, sans-serif; }
    main { min-height: 100vh; display: grid; place-items: center; padding: 2rem 1.25rem; }
    section { max-width: 30rem; width: 100%; padding: clamp(1.5rem, 6vw, 3rem); background: #fffaf5;
      border: 1px solid #ebd9cd; border-radius: 1rem; }
    h1 { margin: .5rem 0 1rem; font-size: clamp(1.85rem, 5vw, 2.5rem); line-height: 1.15; }
    p { margin: 0 0 1.25rem; }
    .brand { margin: 0; color: #794431; font-weight: 700; }
    .note { margin: 1.25rem 0 0; color: #594b42; font-size: .875rem; }
    .actions { display: flex; flex-wrap: wrap; gap: .75rem; }
    button { cursor: pointer; min-height: 44px; padding: .55rem .85rem; border-radius: .5rem;
      border: 1px solid #883d27; background: #883d27; color: #fff; font: inherit; font-weight: 600; }
    button.secondary { background: transparent; color: #79351f; }
    button:focus-visible, p:focus-visible { outline: 2px solid #79351f; outline-offset: .2rem; }
    [hidden] { display: none; }
  </style>
</head>
<body>
  <main>
    <section aria-labelledby="invitation-title">
      <p class="brand">AfterTime</p>
      <h1 id="invitation-title">Capsule invitation</h1>
      <p id="invitation-status" role="status" tabindex="-1">Checking the invitation…</p>
      <div id="authentication-actions" class="actions" hidden>
        <button id="test-session" type="button">Use test session</button>
        <button id="interrupt-sign-in" type="button" class="secondary">Simulate sign-in redirect</button>
      </div>
      <button id="claim-invitation" type="button" hidden>Claim invitation</button>
      <noscript><p>Enable JavaScript to open the local invitation.</p></noscript>
      <p class="note">Local prototype with simulated sign-in and claim.</p>
    </section>
  </main>
</body>
</html>`, {
    headers: { ...privacyHeaders, "Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": policy },
  });
}
