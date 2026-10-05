/** The admin page at `/admin`. Static; `client.ts` does the rest. See ADR 0021, looks per ADR 0029. */

export const ADMIN_HTML = `<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>inkhash · Verwaltung</title>
<style>
  /* Paper on a desk, like the website and the app: ADR 0029, palette from Website/index.html. Light only. */
  :root {
    --paper: #fdfdfc;
    --desk-top: #f6f6f7;
    --desk-bottom: #eceef0;
    --ink: #1c1d20;
    --muted: #6b7078;
    --accent: #3d6fa8;
    --wordmark: #5a616c;
    --line: rgba(28, 29, 32, 0.08);
    --edge: rgba(28, 29, 32, 0.14);
    --bad: #a3392b;
    color-scheme: light;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; }
  html { min-height: 100%; background: var(--desk-bottom) linear-gradient(135deg, var(--desk-top), var(--desk-bottom)) no-repeat; }
  body {
    padding: 16px;
    color: var(--ink);
    font: 16px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  .bar, .sheet { max-width: 30rem; margin: 0 auto; background: var(--paper); border: 1px solid #fff; }
  .bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 10px 16px;
    border-radius: 18px;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.05);
  }
  .bar h1 { display: flex; align-items: center; gap: 8px; margin: 0; color: var(--wordmark); font-size: 19px; font-weight: 600; letter-spacing: -0.4px; }
  .bar .mark { width: 26px; height: 26px; }
  .bar small { color: var(--muted); font-size: 14px; }
  .sheet {
    margin-top: 20px;
    margin-bottom: 32px;
    padding: 40px clamp(20px, 7vw, 48px);
    border-radius: 22px;
    box-shadow: 0 12px 40px rgba(0, 0, 0, 0.07);
  }
  h2 { margin: 0 0 6px; font-size: 26px; line-height: 1.2; letter-spacing: -0.5px; }
  h2.next { margin-top: 40px; font-size: 20px; letter-spacing: -0.3px; }
  p { margin: 0 0 8px; }
  .muted { color: var(--muted); font-size: 15px; }
  form { display: grid; gap: 14px; margin-top: 20px; }
  label { display: grid; gap: 6px; font-size: 14px; color: var(--muted); }
  input {
    font: inherit;
    color: var(--ink);
    background: var(--paper);
    border: 1px solid var(--edge);
    border-radius: 10px;
    padding: 10px 12px;
  }
  input:focus { outline: 2px solid var(--accent); outline-offset: 1px; }
  button {
    justify-self: start;
    margin-top: 6px;
    font: inherit;
    font-weight: 600;
    padding: 12px 20px;
    border-radius: 14px;
    color: var(--paper);
    background: var(--ink);
    border: 1px solid var(--ink);
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.05);
    cursor: pointer;
  }
  button:hover { background: #2c2e33; }
  button.quiet { padding: 8px 14px; font-weight: 500; font-size: 15px; color: var(--muted); background: var(--paper); border-color: var(--edge); }
  button.quiet:hover { background: var(--desk-top); }
  button:disabled { opacity: 0.5; cursor: default; }
  #status { margin: 0 0 24px; padding: 10px 14px; border-radius: 12px; color: var(--bad); background: rgba(163, 57, 43, 0.07); }
  #status:empty { display: none; }
  #status.ok { color: var(--accent); background: rgba(61, 111, 168, 0.08); }
  ul { list-style: none; padding: 0; margin: 16px 0 0; border-top: 1px solid var(--line); }
  li { display: flex; justify-content: space-between; align-items: center; gap: 16px; padding: 10px 0; border-bottom: 1px solid var(--line); }
  li .muted:not(:empty) { font-size: 13px; padding: 2px 10px; border-radius: 999px; background: var(--desk-top); border: 1px solid var(--line); }
  .leave { margin: 32px 0 0; }
  [hidden] { display: none !important; }
</style>
</head>
<body>
<header class="bar">
  <h1><svg class="mark" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" aria-hidden="true"><g fill="#8c9199"><path d="M37.72 4.47 L36.57 7.16 L35.44 9.87 L34.4 12.59 L33.45 15.33 L32.62 18.11 L31.92 20.91 L31.27 23.72 L30.61 26.53 L29.95 29.35 L29.3 32.16 L28.64 34.97 L27.99 37.78 L27.33 40.6 L26.67 43.41 L26.02 46.22 L25.36 49.03 L24.7 51.85 L24.05 54.66 L23.43 57.48 L22.85 60.31 L22.3 63.15 L21.79 65.99 L21.31 68.85 L20.87 71.71 L20.45 74.58 L20.06 77.45 L19.7 80.33 L19.35 83.22 L19.02 86.11 L18.7 89 L18.39 91.89 L18.09 94.79 L19.91 95.21 L20.92 92.48 L21.92 89.75 L22.92 87.02 L23.9 84.28 L24.87 81.54 L25.81 78.8 L26.74 76.05 L27.63 73.29 L28.5 70.53 L29.34 67.76 L30.14 64.98 L30.9 62.19 L31.63 59.39 L32.32 56.59 L32.98 53.78 L33.64 50.97 L34.3 48.15 L34.95 45.34 L35.61 42.53 L36.26 39.72 L36.92 36.9 L37.58 34.09 L38.23 31.28 L38.89 28.47 L39.55 25.65 L40.2 22.84 L40.82 20.02 L41.3 17.17 L41.67 14.29 L41.93 11.38 L42.12 8.46 L42.28 5.53Z"/><circle cx="40" cy="5" r="2.34"/><circle cx="19" cy="95" r="0.94"/></g><g fill="#1c1c1f"><path d="M12.32 42.45 L15.02 42.65 L17.71 42.81 L20.39 42.89 L23.05 42.86 L25.7 42.7 L28.33 42.4 L30.96 42.06 L33.58 41.71 L36.21 41.37 L38.83 41.02 L41.46 40.68 L44.08 40.34 L46.71 39.99 L49.33 39.65 L51.96 39.31 L54.58 38.96 L57.21 38.62 L59.83 38.27 L62.45 37.89 L65.07 37.47 L67.68 37.01 L70.28 36.51 L72.88 35.97 L75.48 35.4 L78.07 34.79 L80.66 34.16 L83.24 33.51 L85.82 32.83 L88.4 32.13 L90.98 31.42 L93.55 30.7 L96.13 29.98 L95.87 28.02 L93.2 27.98 L90.52 27.95 L87.85 27.93 L85.18 27.92 L82.51 27.93 L79.84 27.96 L77.18 28.02 L74.52 28.1 L71.87 28.22 L69.22 28.37 L66.57 28.56 L63.93 28.78 L61.3 29.05 L58.67 29.35 L56.04 29.69 L53.42 30.04 L50.79 30.38 L48.17 30.73 L45.54 31.07 L42.92 31.41 L40.29 31.76 L37.67 32.1 L35.04 32.44 L32.42 32.79 L29.79 33.13 L27.17 33.48 L24.55 33.86 L21.95 34.39 L19.36 35.05 L16.79 35.82 L14.23 36.66 L11.68 37.55Z"/><circle cx="12" cy="40" r="2.48"/><circle cx="96" cy="29" r="0.99"/></g><g fill="#1c1c1f"><path d="M3.29 69.46 L6.01 69.69 L8.72 69.88 L11.43 69.99 L14.12 69.99 L16.8 69.86 L19.46 69.59 L22.12 69.28 L24.78 68.97 L27.43 68.66 L30.09 68.34 L32.74 68.03 L35.4 67.72 L38.06 67.41 L40.71 67.09 L43.37 66.78 L46.03 66.47 L48.68 66.16 L51.34 65.84 L53.99 65.49 L56.64 65.1 L59.28 64.67 L61.92 64.2 L64.55 63.69 L67.18 63.15 L69.81 62.58 L72.43 61.98 L75.05 61.35 L77.66 60.71 L80.28 60.04 L82.89 59.36 L85.5 58.68 L88.12 57.98 L87.88 56.02 L85.18 55.95 L82.48 55.89 L79.78 55.83 L77.09 55.79 L74.39 55.77 L71.7 55.77 L69.01 55.79 L66.32 55.85 L63.64 55.93 L60.96 56.05 L58.28 56.21 L55.61 56.4 L52.95 56.63 L50.29 56.91 L47.63 57.22 L44.97 57.53 L42.32 57.84 L39.66 58.16 L37.01 58.47 L34.35 58.78 L31.69 59.09 L29.04 59.41 L26.38 59.72 L23.72 60.03 L21.07 60.34 L18.41 60.66 L15.76 61.01 L13.13 61.51 L10.51 62.14 L7.9 62.87 L5.3 63.69 L2.71 64.54Z"/><circle cx="3" cy="67" r="2.48"/><circle cx="88" cy="57" r="0.99"/></g><g fill="#1c1c1f"><path d="M67.5 2.25 L66.1 4.9 L64.75 7.56 L63.47 10.24 L62.31 12.95 L61.28 15.71 L60.39 18.51 L59.54 21.32 L58.7 24.14 L57.86 26.95 L57.01 29.76 L56.17 32.57 L55.33 35.39 L54.48 38.2 L53.64 41.01 L52.79 43.82 L51.95 46.64 L51.11 49.45 L50.27 52.26 L49.46 55.08 L48.7 57.92 L47.97 60.77 L47.29 63.63 L46.64 66.5 L46.03 69.38 L45.45 72.28 L44.9 75.18 L44.38 78.08 L43.87 81 L43.39 83.92 L42.92 86.84 L42.46 89.77 L42 92.7 L44 93.3 L45.23 90.6 L46.46 87.91 L47.67 85.2 L48.88 82.5 L50.06 79.79 L51.22 77.07 L52.36 74.35 L53.47 71.62 L54.55 68.87 L55.59 66.12 L56.59 63.36 L57.55 60.58 L58.48 57.79 L59.36 54.99 L60.21 52.18 L61.05 49.36 L61.89 46.55 L62.74 43.74 L63.58 40.93 L64.42 38.11 L65.27 35.3 L66.11 32.49 L66.96 29.68 L67.8 26.86 L68.64 24.05 L69.49 21.24 L70.29 18.41 L70.94 15.55 L71.47 12.64 L71.88 9.69 L72.21 6.73 L72.5 3.75Z"/><circle cx="70" cy="3" r="2.61"/><circle cx="43" cy="93" r="1.04"/></g></svg><span>inkhash</span></h1>
  <small>Verwaltung</small>
</header>
<main class="sheet">
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
    <h2 class="next">Account anlegen</h2>
    <p class="muted">Name und Startpasswort gibst du selbst weiter. Damit meldet sich die Person in der App an.</p>
    <form id="create-form" method="post">
      <label>Name <input name="name" autocomplete="off" autocapitalize="none" spellcheck="false" required></label>
      <label>Startpasswort, mindestens 8 Zeichen <input name="password" autocomplete="off" autocapitalize="none" spellcheck="false" minlength="8" required></label>
      <button>Account anlegen</button>
    </form>
    <p class="leave"><button id="logout" class="quiet" type="button">Abmelden</button></p>
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
