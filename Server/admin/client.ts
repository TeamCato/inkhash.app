/// <reference lib="dom" />
/** Runs in the browser on `/admin`. Talks to the same JSON API as the app. See ADR 0021. */

export {};

const SESSION_KEY = "inkhash-admin-session";

interface Answer {
  status: number;
  data: Record<string, unknown>;
}

interface AccountRow {
  id: string;
  name: string;
  admin: boolean;
}

/** The signed-in admin's own account id, from the account list. */
let me = "";

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
  if (reason === "last admin") return "Der letzte Admin bleibt Admin und lässt sich nicht löschen.";
  if (answer.status === 404) return "Diesen Account gibt es nicht mehr.";
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
  const admins = rows.filter((row) => row.admin).length;
  const list = element<HTMLUListElement>("accounts");
  list.replaceChildren(...rows.map((row) => accountItem(row, row.admin && admins <= 1)));
}

function badge(text: string): HTMLSpanElement {
  const span = document.createElement("span");
  span.className = "badge";
  span.textContent = text;
  return span;
}

function button(text: string, className: string, action: () => Promise<void>): HTMLButtonElement {
  const control = document.createElement("button");
  control.type = "button";
  control.className = className;
  control.textContent = text;
  control.addEventListener("click", () => {
    control.disabled = true;
    action()
      .catch(() => say("Server nicht erreichbar."))
      .finally(() => {
        control.disabled = false;
      });
  });
  return control;
}

/** A small form with one field and a button, for renaming and new passwords. */
function inlineForm(label: string, input: Partial<HTMLInputElement>, submit: string, action: (value: string) => Promise<void>): HTMLFormElement {
  const form = document.createElement("form");
  const field = document.createElement("label");
  field.textContent = label;
  const box = document.createElement("input");
  Object.assign(box, { autocomplete: "off", autocapitalize: "none", spellcheck: false, required: true }, input);
  field.append(box);
  const send = document.createElement("button");
  send.className = "quiet";
  send.textContent = submit;
  form.append(field, send);
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    void busy(form, () => action(box.value));
  });
  return form;
}

/** One account: name and role, and behind "Bearbeiten" what the admin can change. See ADR 0046. */
function accountItem(row: AccountRow, lastAdmin: boolean): HTMLLIElement {
  const item = document.createElement("li");
  const head = document.createElement("div");
  head.className = "head";
  const name = document.createElement("span");
  name.textContent = row.name;
  const badges = document.createElement("span");
  badges.className = "badges";
  if (row.id === me) badges.append(badge("du"));
  if (row.admin) badges.append(badge("Admin"));
  head.append(name, badges);

  const details = document.createElement("details");
  const summary = document.createElement("summary");
  summary.textContent = "Bearbeiten";
  const rename = inlineForm("Neuer Name", { value: row.name }, "Umbenennen", async (value) => {
    if (await change(row, { name: value })) say(`${row.name} heißt jetzt ${value.trim().toLowerCase()}.`, true);
  });
  const password = inlineForm("Neues Passwort, mindestens 8 Zeichen", { minLength: 8 }, "Passwort setzen", async (value) => {
    if (await change(row, { password: value })) {
      say(`Neues Passwort für ${row.name} gesetzt. Seine Geräte müssen sich damit neu anmelden.`, true);
    }
  });
  const actions = document.createElement("div");
  actions.className = "actions";
  const role = row.admin
    ? button("Admin-Rechte entziehen", "quiet", async () => {
        if (await change(row, { admin: false })) say(`${row.name} ist kein Admin mehr.`, true);
      })
    : button("Zum Admin machen", "quiet", async () => {
        if (await change(row, { admin: true })) say(`${row.name} ist jetzt Admin.`, true);
      });
  const remove = button("Account löschen", "quiet danger", () => removeAccount(row));
  role.disabled = lastAdmin;
  remove.disabled = lastAdmin;
  actions.append(role, remove);
  details.append(summary, rename, password, actions);
  if (lastAdmin) {
    const note = document.createElement("p");
    note.className = "muted";
    note.textContent = "Der letzte Admin bleibt Admin und lässt sich nicht löschen. Mach zuerst jemand anderen zum Admin.";
    details.append(note);
  }
  item.append(head, details);
  return item;
}

/** Sends a change and shows the list again. False if it failed; the reason is shown. */
async function change(row: AccountRow, body: Record<string, unknown>): Promise<boolean> {
  const answer = await api("PATCH", `/v1/accounts/${row.id}`, body, true);
  if (answer.status !== 200) {
    failed(answer);
    return false;
  }
  await openAdmin();
  return true;
}

async function removeAccount(row: AccountRow): Promise<void> {
  const own = row.id === me ? "\n\nDas ist dein eigener Account; du wirst danach abgemeldet." : "";
  const sure = window.confirm(
    `Account ${row.name} löschen?\n\nEr kann sich nicht mehr anmelden. Seine Geräte gleichen nicht mehr ab und behalten ihre Notizen. ` +
      `Auf dem Server verschwinden seine Notizen; zurückholen kann sie nur, wer Zugriff auf den Server hat.${own}`,
  );
  if (!sure) return;
  const answer = await api("DELETE", `/v1/accounts/${row.id}`, undefined, true);
  if (answer.status !== 204) {
    failed(answer);
    return;
  }
  if (row.id === me) {
    writeSession(null);
    show("login");
  } else {
    await openAdmin();
  }
  say(`Account ${row.name} gelöscht.`, true);
}

function failed(answer: Answer): void {
  if (answer.status === 401) {
    writeSession(null);
    show("login");
    say("Anmeldung abgelaufen.");
    return;
  }
  say(explain(answer, "Anmeldung abgelaufen."));
}

function accountRows(answer: Answer): AccountRow[] {
  const raw = answer.data.accounts;
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((entry: unknown) => {
    if (typeof entry !== "object" || entry === null) return [];
    const record = entry as Record<string, unknown>;
    return typeof record.name === "string" && typeof record.id === "string"
      ? [{ id: record.id, name: record.name, admin: record.admin === true }]
      : [];
  });
}

/** Shows the account list if the stored session belongs to the admin, else the login. */
async function openAdmin(): Promise<void> {
  const answer = await api("GET", "/v1/accounts", undefined, true);
  if (answer.status === 200) {
    me = typeof answer.data.me === "string" ? answer.data.me : "";
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
  if (typeof health.data.version === "string") element("version").textContent = ` · Server ${health.data.version}`;
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
