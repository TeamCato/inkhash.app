/// <reference lib="dom" />
/** Runs in the browser on `/admin`. Talks to the same JSON API as the app. See ADR 0021. */

export {};

const SESSION_KEY = "inkhash-admin-session";

interface Answer {
  status: number;
  data: Record<string, unknown>;
}

interface AccountRow {
  name: string;
  admin: boolean;
}

function element<T extends HTMLElement>(id: string): T {
  const found = document.getElementById(id);
  if (!found) throw new Error(`#${id} missing`);
  return found as T;
}

const sections = {
  setup: element<HTMLElement>("setup"),
  login: element<HTMLElement>("login"),
  admin: element<HTMLElement>("admin"),
};
const statusLine = element<HTMLParagraphElement>("status");

function readSession(): string {
  try {
    return sessionStorage.getItem(SESSION_KEY) ?? "";
  } catch {
    return "";
  }
}

let memorySession = readSession();

function writeSession(token: string | null): void {
  try {
    if (token) sessionStorage.setItem(SESSION_KEY, token);
    else sessionStorage.removeItem(SESSION_KEY);
  } catch {
    // Without storage the session lasts until the page reloads.
  }
  memorySession = token ?? "";
}

function say(text: string, ok = false): void {
  statusLine.textContent = text;
  statusLine.classList.toggle("ok", ok);
}

function show(name: keyof typeof sections): void {
  for (const [key, section] of Object.entries(sections)) section.hidden = key !== name;
}

async function api(method: string, path: string, body?: unknown, authorized = false): Promise<Answer> {
  const headers: Record<string, string> = {};
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (authorized && memorySession) headers.Authorization = `Bearer ${memorySession}`;
  const response = await fetch(path, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    cache: "no-store",
  });
  const text = await response.text();
  let data: Record<string, unknown> = {};
  try {
    const parsed = text ? (JSON.parse(text) as unknown) : {};
    if (typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)) data = parsed as Record<string, unknown>;
  } catch {
    // A body that is not JSON carries no detail worth showing.
  }
  return { status: response.status, data };
}

/** Turns an error answer into a sentence. `unauthorized` depends on what was sent. */
function explain(answer: Answer, unauthorized: string): string {
  const error = answer.data.error;
  const reason = answer.data.reason;
  if (answer.status === 401) return unauthorized;
  if (answer.status === 429) return "Zu viele Fehlversuche. In 15 Minuten noch einmal.";
  if (error === "name-taken") return "Diesen Namen gibt es schon.";
  if (reason === "name") return "Der Name hat 2 bis 32 Zeichen: Kleinbuchstaben, Ziffern, Punkt, Unterstrich, Bindestrich.";
  if (reason === "password") return "Das Passwort braucht 8 bis 200 Zeichen.";
  if (error === "forbidden") return "Dieser Account ist nicht der Admin.";
  return `Der Server antwortete mit ${answer.status}.`;
}

function fields(form: HTMLFormElement): Record<string, string> {
  const values: Record<string, string> = {};
  for (const [key, value] of new FormData(form)) values[key] = typeof value === "string" ? value : "";
  return values;
}

/** Disables the form while a request runs, so a double click does not send twice. */
async function busy(form: HTMLFormElement, work: () => Promise<void>): Promise<void> {
  const button = form.querySelector("button");
  if (button) button.disabled = true;
  try {
    await work();
  } catch {
    say("Server nicht erreichbar.");
  } finally {
    if (button) button.disabled = false;
  }
}

function renderAccounts(rows: AccountRow[]): void {
  const list = element<HTMLUListElement>("accounts");
  list.replaceChildren(
    ...rows.map((row) => {
      const item = document.createElement("li");
      const name = document.createElement("span");
      name.textContent = row.name;
      const role = document.createElement("span");
      role.className = "muted";
      role.textContent = row.admin ? "Admin" : "";
      item.append(name, role);
      return item;
    }),
  );
}

function accountRows(answer: Answer): AccountRow[] {
  const raw = answer.data.accounts;
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((entry: unknown) => {
    if (typeof entry !== "object" || entry === null) return [];
    const record = entry as Record<string, unknown>;
    return typeof record.name === "string" ? [{ name: record.name, admin: record.admin === true }] : [];
  });
}

/** Shows the account list if the stored session belongs to the admin, else the login. */
async function openAdmin(): Promise<void> {
  const answer = await api("GET", "/v1/accounts", undefined, true);
  if (answer.status === 200) {
    renderAccounts(accountRows(answer));
    show("admin");
    return;
  }
  if (answer.status === 403) {
    await api("DELETE", "/v1/session", undefined, true);
    say("Dieser Account ist nicht der Admin.");
  }
  writeSession(null);
  show("login");
}

async function start(): Promise<void> {
  const health = await api("GET", "/v1/health");
  if (health.data.registration === "setup") {
    writeSession(null);
    show("setup");
    return;
  }
  if (memorySession) await openAdmin();
  else show("login");
}

element<HTMLFormElement>("setup-form").addEventListener("submit", (event) => {
  event.preventDefault();
  const form = event.currentTarget as HTMLFormElement;
  const values = fields(form);
  if (values.password !== values.repeat) {
    say("Die Passwörter stimmen nicht überein.");
    return;
  }
  void busy(form, async () => {
    const answer = await api("POST", "/v1/setup", {
      setupToken: (values.setupToken ?? "").trim(),
      name: values.name,
      password: values.password,
    });
    if (answer.status === 403 && answer.data.error === "setup-done") {
      say("Der Server ist schon eingerichtet. Bitte anmelden.");
      show("login");
      return;
    }
    if (answer.status !== 201) {
      say(explain(answer, "Der Setup-Token stimmt nicht."));
      return;
    }
    writeSession(typeof answer.data.token === "string" ? answer.data.token : null);
    form.reset();
    say("Admin angelegt. Der Setup-Token gilt nicht mehr.", true);
    await openAdmin();
  });
});

element<HTMLFormElement>("login-form").addEventListener("submit", (event) => {
  event.preventDefault();
  const form = event.currentTarget as HTMLFormElement;
  const values = fields(form);
  void busy(form, async () => {
    const answer = await api("POST", "/v1/session", { name: values.name, password: values.password });
    if (answer.status !== 200) {
      say(explain(answer, "Name oder Passwort stimmt nicht."));
      return;
    }
    writeSession(typeof answer.data.token === "string" ? answer.data.token : null);
    form.reset();
    say("");
    await openAdmin();
  });
});

element<HTMLFormElement>("create-form").addEventListener("submit", (event) => {
  event.preventDefault();
  const form = event.currentTarget as HTMLFormElement;
  const values = fields(form);
  void busy(form, async () => {
    const answer = await api("POST", "/v1/accounts", { name: values.name, password: values.password }, true);
    if (answer.status === 401) {
      writeSession(null);
      show("login");
      say("Anmeldung abgelaufen.");
      return;
    }
    if (answer.status !== 201) {
      say(explain(answer, "Anmeldung abgelaufen."));
      return;
    }
    form.reset();
    say(`Account ${String(answer.data.name)} angelegt.`, true);
    await openAdmin();
  });
});

element<HTMLButtonElement>("logout").addEventListener("click", () => {
  void (async () => {
    try {
      await api("DELETE", "/v1/session", undefined, true);
    } catch {
      // The session ends here either way.
    }
    writeSession(null);
    say("");
    show("login");
  })();
});

start().catch(() => say("Server nicht erreichbar."));
