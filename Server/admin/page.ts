/** The admin page at `/admin`. Static; `client.ts` does the rest. See ADR 0021. */

export const ADMIN_HTML = `<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>Inkhash · Verwaltung</title>
<style>
  :root { color-scheme: light dark; --ink: #1d1b19; --muted: #6f6a63; --paper: #f7f4ee; --line: #ddd6cb; --accent: #2f5d50; --bad: #a3392b; }
  @media (prefers-color-scheme: dark) {
    :root { --ink: #ece7df; --muted: #a59f96; --paper: #1b1a18; --line: #3a3733; --accent: #7fb8a6; --bad: #e08070; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--paper); color: var(--ink); font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  main { max-width: 26rem; margin: 0 auto; padding: 3rem 1rem; }
  h1 { font-size: 1.5rem; margin: 0 0 0.25rem; }
  h2 { font-size: 1.1rem; margin: 2rem 0 0.5rem; }
  p { margin: 0.5rem 0; }
  .muted { color: var(--muted); font-size: 0.9rem; }
  form { display: grid; gap: 0.75rem; margin-top: 1rem; }
  label { display: grid; gap: 0.25rem; font-size: 0.9rem; color: var(--muted); }
  input { font: inherit; color: var(--ink); background: transparent; border: 1px solid var(--line); border-radius: 6px; padding: 0.5rem 0.6rem; }
  input:focus { outline: 2px solid var(--accent); outline-offset: -1px; border-color: transparent; }
  button { font: inherit; border: 0; border-radius: 6px; padding: 0.55rem 0.9rem; background: var(--accent); color: var(--paper); cursor: pointer; justify-self: start; }
  button.quiet { background: transparent; color: var(--muted); padding: 0; text-decoration: underline; }
  button:disabled { opacity: 0.5; cursor: default; }
  ul { list-style: none; padding: 0; margin: 0.5rem 0 0; border-top: 1px solid var(--line); }
  li { display: flex; justify-content: space-between; gap: 1rem; padding: 0.5rem 0; border-bottom: 1px solid var(--line); }
  #status { margin-top: 1rem; color: var(--bad); }
  #status:empty { display: none; }
  #status.ok { color: var(--accent); }
  [hidden] { display: none !important; }
</style>
</head>
<body>
<main>
  <h1>Inkhash</h1>
  <p class="muted">Verwaltung dieses Servers</p>
  <p id="status" role="status"></p>

  <section id="setup" hidden>
    <h2>Einrichten</h2>
    <p class="muted">Den Setup-Token schreibt der Server beim Start in sein Log. Er gilt, bis du hier den Admin angelegt hast. Der Admin ist ein normaler Account für die App und kann zusätzlich weitere Accounts anlegen.</p>
    <form id="setup-form" method="post">
      <label>Setup-Token <input name="setupToken" autocomplete="off" autocapitalize="none" spellcheck="false" required></label>
      <label>Name <input name="name" autocomplete="username" autocapitalize="none" spellcheck="false" required></label>
      <label>Passwort, mindestens 8 Zeichen <input name="password" type="password" autocomplete="new-password" minlength="8" required></label>
      <label>Passwort wiederholen <input name="repeat" type="password" autocomplete="new-password" minlength="8" required></label>
      <button>Admin anlegen</button>
    </form>
  </section>

  <section id="login" hidden>
    <h2>Anmelden</h2>
    <p class="muted">Als Admin, mit Name und Passwort aus der App.</p>
    <form id="login-form" method="post">
      <label>Name <input name="name" autocomplete="username" autocapitalize="none" spellcheck="false" required></label>
      <label>Passwort <input name="password" type="password" autocomplete="current-password" required></label>
      <button>Anmelden</button>
    </form>
  </section>

  <section id="admin" hidden>
    <h2>Accounts</h2>
    <ul id="accounts"></ul>
    <h2>Account anlegen</h2>
    <p class="muted">Name und Startpasswort gibst du selbst weiter. Damit meldet sich die Person in der App an.</p>
    <form id="create-form" method="post">
      <label>Name <input name="name" autocomplete="off" autocapitalize="none" spellcheck="false" required></label>
      <label>Startpasswort, mindestens 8 Zeichen <input name="password" autocomplete="off" autocapitalize="none" spellcheck="false" minlength="8" required></label>
      <button>Account anlegen</button>
    </form>
    <p style="margin-top: 2rem"><button id="logout" class="quiet" type="button">Abmelden</button></p>
  </section>

</main>
<script type="module" src="/admin/client.js"></script>
</body>
</html>
`;

/** Only the page's own script runs, nothing may frame it, and forms never submit without it. */
export const ADMIN_CSP = [
  "default-src 'none'",
  "script-src 'self'",
  "connect-src 'self'",
  "style-src 'unsafe-inline'",
  "form-action 'none'",
  "frame-ancestors 'none'",
  "base-uri 'none'",
].join("; ");
