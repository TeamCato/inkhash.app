import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import type { Server } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import {
  Accounts,
  CLIENT_LOCK_AFTER,
  MAX_HASHING,
  MAX_HASHING_PER_CLIENT,
  NAME_LOCK_AFTER,
  SESSION_IDLE_DAYS,
  Throttle,
  clientKey,
} from "../accounts.js";
import { adminAddress, serve, trustedProxies, type ServeOptions } from "../inkhashd.js";
import { Store, StoreError, type Note } from "../store.js";

function textNote(id: string, markdown = "# Hallo\n", tags: string[] = []): Note {
  return {
    schemaVersion: 1,
    id,
    kind: "text",
    title: "Hallo",
    revision: 0,
    updatedAt: "2026-09-30T06:00:00Z",
    deletedAt: null,
    markdown,
    transcript: null,
    tags,
    pages: null,
    folder: "",
    favorite: false,
  };
}

function listen(server: Server): Promise<number> {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (address && typeof address === "object") resolve(address.port);
      else reject(new Error("no port"));
    });
  });
}

async function withServer(
  fn: (port: number, root: string) => Promise<void>,
  options: ServeOptions = {},
): Promise<void> {
  const root = mkdtempSync(join(tmpdir(), "inkhash-"));
  const accounts = new Accounts(root, 1_000, "test-token");
  const server = serve(accounts, options);
  try {
    const port = await listen(server);
    await fn(port, root);
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    rmSync(root, { recursive: true, force: true });
  }
}

async function request(
  port: number,
  method: string,
  path: string,
  body?: unknown,
  token: string | null = "test-token",
): Promise<{ status: number; raw: Buffer }> {
  const payload = body == null ? undefined : Buffer.isBuffer(body) ? body : JSON.stringify(body);
  const headers: Record<string, string> = {};
  if (token != null) headers.Authorization = `Bearer ${token}`;
  if (payload != null && typeof payload !== "string") headers["Content-Type"] = "application/octet-stream";
  if (typeof payload === "string") headers["Content-Type"] = "application/json";
  const response = await fetch(`http://127.0.0.1:${port}${path}`, {
    method,
    headers,
    body: typeof payload === "string" ? payload : payload ? new Uint8Array(payload) : undefined,
  });
  return { status: response.status, raw: Buffer.from(await response.arrayBuffer()) };
}

type Opened = { token: string; account: { id: string; name: string; admin: boolean } };

/** Sets the server up: the first account is the admin. */
async function openAccount(port: number, name = "ada", password = "secretsecret"): Promise<Opened> {
  const { status, raw } = await request(port, "POST", "/v1/setup", { name, password, setupToken: "test-token" }, null);
  assert.equal(status, 201, raw.toString("utf8"));
  return JSON.parse(raw.toString("utf8")) as Opened;
}

/** The admin creates another account, which then signs in like the app does. */
async function addAccount(port: number, admin: string, name: string, password = "secretsecret"): Promise<Opened> {
  const created = await request(port, "POST", "/v1/accounts", { name, password }, admin);
  assert.equal(created.status, 201, created.raw.toString("utf8"));
  const { status, raw } = await request(port, "POST", "/v1/session", { name, password }, null);
  assert.equal(status, 200, raw.toString("utf8"));
  return JSON.parse(raw.toString("utf8")) as Opened;
}

test("health is open and notes need a session", async () => {
  await withServer(async (port) => {
    const { status, raw } = await request(port, "GET", "/v1/health", undefined, null);
    assert.equal(status, 200);
    const health = JSON.parse(raw.toString("utf8")) as { ok: boolean; registration: string; version: string };
    assert.equal(health.ok, true);
    assert.equal(health.registration, "setup");
    // The version comes from package.json, which releases set; here it is the checkout's.
    const packaged = JSON.parse(readFileSync(new URL("../../package.json", import.meta.url), "utf8")) as { version: string };
    assert.equal(health.version, packaged.version);
    const denied = await request(port, "GET", "/v1/changes?after=0", undefined, "test-token");
    assert.equal(denied.status, 401);
  });
});

test("setup creates the admin once, then the token is spent", async () => {
  await withServer(async (port) => {
    const wrong = await request(port, "POST", "/v1/setup", { name: "ada", password: "secretsecret", setupToken: "nope" }, null);
    assert.equal(wrong.status, 401);
    const ada = await openAccount(port);
    assert.equal(ada.account.admin, true);
    const again = await request(
      port,
      "POST",
      "/v1/setup",
      { name: "bea", password: "secretsecret", setupToken: "test-token" },
      null,
    );
    assert.equal(again.status, 403);
    assert.equal(body<{ error: string }>(again.raw).error, "setup-done");
    const invalid = await request(port, "POST", "/v1/setup", { name: "", password: "" }, null);
    assert.equal(invalid.status, 403, "setup-done before the body is checked");
    const health = await request(port, "GET", "/v1/health", undefined, null);
    assert.equal(body<{ registration: string }>(health.raw).registration, "closed");
    assert.equal((await request(port, "GET", "/v1/changes", undefined, "test-token")).status, 401, "setup token is no login");
  });
});

test("only the admin creates accounts, and notes stay apart", async () => {
  await withServer(async (port) => {
    const ada = await openAccount(port);
    const anonymous = await request(port, "POST", "/v1/accounts", { name: "cy", password: "secretsecret" }, null);
    assert.equal(anonymous.status, 401);
    const bea = await addAccount(port, ada.token, "bea");
    assert.equal(bea.account.admin, false);
    const byBea = await request(port, "POST", "/v1/accounts", { name: "cy", password: "secretsecret" }, bea.token);
    assert.equal(byBea.status, 403);
    assert.equal((await request(port, "GET", "/v1/accounts", undefined, bea.token)).status, 403);
    const taken = await request(port, "POST", "/v1/accounts", { name: "bea", password: "secretsecret" }, ada.token);
    assert.equal(taken.status, 409);
    assert.equal(body<{ error: string }>(taken.raw).error, "name-taken");
    const short = await request(port, "POST", "/v1/accounts", { name: "cy", password: "short" }, ada.token);
    assert.equal(short.status, 400);
    const listed = body<{ accounts: { name: string; admin: boolean }[] }>(
      (await request(port, "GET", "/v1/accounts", undefined, ada.token)).raw,
    );
    assert.deepEqual(
      listed.accounts.map((account) => [account.name, account.admin]),
      [["ada", true], ["bea", false]],
    );

    const noteId = "6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10";
    const created = await request(
      port,
      "PUT",
      `/v1/notes/${noteId}`,
      { baseRevision: 0, note: textNote(noteId, "# Hallo\n", ["eigen"]) },
      ada.token,
    );
    assert.equal(created.status, 201);
    assert.deepEqual((JSON.parse(created.raw.toString("utf8")) as Note).tags, ["eigen"]);
    const hidden = await request(port, "GET", `/v1/notes/${noteId}`, undefined, bea.token);
    assert.equal(hidden.status, 404);
    assert.notEqual(ada.account.id, "");
  });
});

test("login and logout", async () => {
  await withServer(async (port) => {
    await openAccount(port);
    const wrong = await request(port, "POST", "/v1/session", { name: "ada", password: "wrongwrong" }, null);
    assert.equal(wrong.status, 401);
    const session = await request(port, "POST", "/v1/session", { name: "ada", password: "secretsecret" }, null);
    assert.equal(session.status, 200);
    const token = (JSON.parse(session.raw.toString("utf8")) as { token: string }).token;
    assert.equal((await request(port, "GET", "/v1/changes?after=0", undefined, token)).status, 200);
    assert.equal((await request(port, "DELETE", "/v1/session", undefined, token)).status, 204);
    assert.equal((await request(port, "GET", "/v1/changes?after=0", undefined, token)).status, 401);
  });
});

test("first account keeps existing notes", async () => {
  await withServer(async (port, root) => {
    const noteId = "8a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d";
    new Store(root).putNote(noteId, 0, textNote(noteId));
    const { token } = await openAccount(port, "old");
    const { status, raw } = await request(port, "GET", `/v1/notes/${noteId}`, undefined, token);
    assert.equal(status, 200);
    assert.equal((JSON.parse(raw.toString("utf8")) as Note).title, "Hallo");
  });
});

function body<T>(raw: Buffer): T {
  return JSON.parse(raw.toString("utf8")) as T;
}

const NOTE = "6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10";

test("conflict carries the server note, unknown base is not found", async () => {
  await withServer(async (port) => {
    const { token } = await openAccount(port);
    await request(port, "PUT", `/v1/notes/${NOTE}`, { baseRevision: 0, note: textNote(NOTE, "eins") }, token);
    await request(port, "PUT", `/v1/notes/${NOTE}`, { baseRevision: 1, note: textNote(NOTE, "zwei") }, token);
    const conflict = await request(port, "PUT", `/v1/notes/${NOTE}`, { baseRevision: 1, note: textNote(NOTE, "drei") }, token);
    assert.equal(conflict.status, 409);
    const payload = body<{ error: string; note: Note }>(conflict.raw);
    assert.equal(payload.error, "conflict");
    assert.equal(payload.note.markdown, "zwei");

    const other = "8a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d";
    const lost = await request(port, "PUT", `/v1/notes/${other}`, { baseRevision: 3, note: textNote(other) }, token);
    assert.equal(lost.status, 404);
    assert.equal(body<{ error: string }>(lost.raw).error, "not-found");
  });
});

test("changes are paged over HTTP", async () => {
  await withServer(async (port) => {
    const { token } = await openAccount(port);
    const ids = ["6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10", "8a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d"];
    for (const id of ids) {
      await request(port, "PUT", `/v1/notes/${id}`, { baseRevision: 0, note: textNote(id) }, token);
    }
    const first = await request(port, "GET", "/v1/changes?after=0&limit=1", undefined, token);
    const page = body<{ cursor: number; hasMore: boolean; changes: unknown[] }>(first.raw);
    assert.deepEqual([page.cursor, page.hasMore, page.changes.length], [1, true, 1]);
    const rest = body<{ cursor: number; hasMore: boolean }>(
      (await request(port, "GET", `/v1/changes?after=${page.cursor}&limit=1`, undefined, token)).raw,
    );
    assert.deepEqual([rest.cursor, rest.hasMore], [2, false]);
    assert.equal((await request(port, "GET", "/v1/changes?after=0&limit=0", undefined, token)).status, 400);
  });
});

test("blobs over HTTP, with a size limit", async () => {
  await withServer(
    async (port) => {
      const { token } = await openAccount(port);
      const payload = Buffer.from("stroke");
      const digest = createHash("sha256").update(payload).digest("hex");
      assert.equal((await request(port, "PUT", `/v1/blobs/${"a".repeat(64)}`, payload, token)).status, 400);
      assert.equal((await request(port, "PUT", `/v1/blobs/${digest}`, payload, token)).status, 204);
      const fetched = await request(port, "GET", `/v1/blobs/${digest}`, undefined, token);
      assert.equal(fetched.status, 200);
      assert.deepEqual(fetched.raw, payload);
      const big = Buffer.alloc(64, 1);
      const bigDigest = createHash("sha256").update(big).digest("hex");
      assert.equal((await request(port, "PUT", `/v1/blobs/${bigDigest}`, big, token)).status, 413);
      assert.equal((await request(port, "GET", "/v1/health", undefined, null)).status, 200, "server still answers");
    },
    { maxBlob: 32 },
  );
});

test("unknown path is 404, wrong method is 405", async () => {
  await withServer(async (port) => {
    assert.equal((await request(port, "GET", "/v1/nothing", undefined, null)).status, 404);
    assert.equal((await request(port, "PATCH", "/v1/health", undefined, null)).status, 405);
  });
});

test("wrong passwords lock the name", async () => {
  await withServer(async (port) => {
    await openAccount(port);
    for (let attempt = 0; attempt < NAME_LOCK_AFTER; attempt += 1) {
      const wrong = await request(port, "POST", "/v1/session", { name: "ada", password: "wrongwrong" }, null);
      assert.equal(wrong.status, 401);
    }
    const locked = await request(port, "POST", "/v1/session", { name: "ada", password: "secretsecret" }, null);
    assert.equal(locked.status, 429);
    assert.equal(body<{ error: string }>(locked.raw).error, "slow-down");
  });
});

test("guessing the setup token is slowed down", async () => {
  await withServer(async (port) => {
    for (let attempt = 0; attempt < CLIENT_LOCK_AFTER; attempt += 1) {
      const wrong = await request(
        port,
        "POST",
        "/v1/setup",
        { name: "ada", password: "secretsecret", setupToken: `guess-${attempt}` },
        null,
      );
      assert.equal(wrong.status, 401);
    }
    const blocked = await request(
      port,
      "POST",
      "/v1/setup",
      { name: "ada", password: "secretsecret", setupToken: "test-token" },
      null,
    );
    assert.equal(blocked.status, 429);
  });
});

test("setup token is random per start and gone once an account exists", async () => {
  const root = mkdtempSync(join(tmpdir(), "inkhash-"));
  try {
    const first = new Accounts(root, 1_000);
    const token = first.setupToken ?? "";
    assert.ok(token.length >= 32);
    assert.notEqual(new Accounts(root, 1_000).setupToken, token, "a restart before setup makes a new one");
    await first.setup({ name: "ada", password: "secretsecret", setupToken: token }, "local");
    assert.equal(first.setupToken, null);
    const restarted = new Accounts(root, 1_000);
    assert.equal(restarted.setupToken, null);
    assert.equal(restarted.registration(), "closed");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("accounts from before admins: the oldest becomes admin", async () => {
  const root = mkdtempSync(join(tmpdir(), "inkhash-"));
  try {
    const setup = new Accounts(root, 1_000, "t");
    const ada = await setup.setup({ name: "ada", password: "secretsecret", setupToken: "t" }, "local");
    await setup.createAccount(ada.account.id, { name: "bea", password: "secretsecret" });
    for (const [name, createdAt] of [["ada", "2026-05-02T00:00:00Z"], ["bea", "2026-05-01T00:00:00Z"]]) {
      const path = join(root, "identities", `${name}.json`);
      const { admin: _admin, ...legacy } = JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
      writeFileSync(path, JSON.stringify({ ...legacy, createdAt }));
    }
    const migrated = new Accounts(root, 1_000);
    const bea = await migrated.login({ name: "bea", password: "secretsecret" }, "local");
    assert.equal(bea.account.admin, true);
    assert.equal(migrated.setupToken, null);
    assert.deepEqual(
      migrated.listAccounts(bea.account.id).map((account) => [account.name, account.admin]),
      [["ada", false], ["bea", true]],
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("admin page is served with a strict policy", async () => {
  await withServer(async (port) => {
    const page = await fetch(`http://127.0.0.1:${port}/admin`);
    assert.equal(page.status, 200);
    assert.match(page.headers.get("content-type") ?? "", /^text\/html/);
    assert.match(page.headers.get("content-security-policy") ?? "", /script-src 'self'/);
    assert.match(await page.text(), /src="\/admin\/client\.js"/);
    const script = await fetch(`http://127.0.0.1:${port}/admin/client.js`);
    assert.equal(script.status, 200);
    assert.match(script.headers.get("content-type") ?? "", /^text\/javascript/);
    assert.match(await script.text(), /\/v1\/setup/);
    assert.equal((await request(port, "POST", "/admin", {}, null)).status, 405);
  });
});

test("admin address names the host the server listens on", () => {
  assert.equal(adminAddress("127.0.0.1", 8787), "http://127.0.0.1:8787/admin");
  assert.equal(adminAddress("0.0.0.0", 8787), "http://<this host>:8787/admin");
  assert.equal(adminAddress("::1", 8787), "http://[::1]:8787/admin");
});

test("idle session expires and is removed", async () => {
  await withServer(async (port, root) => {
    const { token } = await openAccount(port);
    const path = join(root, "sessions", `${createHash("sha256").update(token).digest("hex")}.json`);
    const record = JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
    const old = new Date(Date.now() - (SESSION_IDLE_DAYS + 1) * 24 * 60 * 60 * 1000).toISOString();
    writeFileSync(path, JSON.stringify({ ...record, lastSeenAt: old }));
    assert.equal((await request(port, "GET", "/v1/changes", undefined, token)).status, 401);
    assert.deepEqual(readdirSync(join(root, "sessions")), []);
  });
});

test("login upgrades a weaker password hash", async () => {
  const root = mkdtempSync(join(tmpdir(), "inkhash-"));
  try {
    await new Accounts(root, 1_000, "t").setup({ name: "ada", password: "secretsecret", setupToken: "t" }, "local");
    const stronger = new Accounts(root, 2_000);
    await stronger.login({ name: "ada", password: "secretsecret" }, "local");
    const identity = JSON.parse(readFileSync(join(root, "identities", "ada.json"), "utf8")) as { passwordHash: string };
    assert.equal(identity.passwordHash.split("$")[1], "2000");
    await stronger.login({ name: "ada", password: "secretsecret" }, "local");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("throttle forgets random keys beyond its bound", () => {
  const throttle = new Throttle(2, 60_000);
  for (let index = 0; index < 10_050; index += 1) throttle.fail(`name-${index}`);
  assert.ok(throttle.size <= 10_000);
});

test("workspaces keep their notes apart, main is the unscoped route", async () => {
  await withServer(async (port) => {
    const ada = await openAccount(port);
    const listed = await request(port, "GET", "/v1/workspaces", undefined, ada.token);
    assert.equal(listed.status, 200);
    assert.deepEqual(JSON.parse(listed.raw.toString("utf8")), {
      workspaces: [{ id: "main", name: "Privat", symbol: null, icon: null, updatedAt: null }],
      ordered: false,
    });

    const created = await request(port, "POST", "/v1/workspaces", { name: "Arbeit" }, ada.token);
    assert.equal(created.status, 201);
    const work = JSON.parse(created.raw.toString("utf8")) as { id: string; name: string };
    assert.equal(work.name, "Arbeit");

    const noteId = "6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10";
    const put = await request(
      port,
      "PUT",
      `/v1/workspaces/${work.id}/notes/${noteId}`,
      { baseRevision: 0, note: { ...textNote(noteId), folder: "Projekte/Inkhash", favorite: true } },
      ada.token,
    );
    assert.equal(put.status, 201);
    const stored = JSON.parse(put.raw.toString("utf8")) as Note;
    assert.equal(stored.folder, "Projekte/Inkhash");
    assert.equal(stored.favorite, true);

    assert.equal((await request(port, "GET", `/v1/notes/${noteId}`, undefined, ada.token)).status, 404);
    assert.equal((await request(port, "GET", `/v1/workspaces/main/notes/${noteId}`, undefined, ada.token)).status, 404);
    const scoped = await request(port, "GET", `/v1/workspaces/${work.id}/changes?after=0`, undefined, ada.token);
    assert.equal((JSON.parse(scoped.raw.toString("utf8")) as { changes: unknown[] }).changes.length, 1);

    const unknown = "11111111-2222-4333-8444-555555555555";
    assert.equal((await request(port, "GET", `/v1/workspaces/${unknown}/changes`, undefined, ada.token)).status, 404);

    const renamed = await request(port, "PATCH", "/v1/workspaces/main", { name: "Zuhause" }, ada.token);
    assert.equal(renamed.status, 200);
    const after = await request(port, "GET", "/v1/workspaces", undefined, ada.token);
    const names = (JSON.parse(after.raw.toString("utf8")) as { workspaces: { name: string }[] }).workspaces.map(
      (workspace) => workspace.name,
    );
    assert.deepEqual(names, ["Zuhause", "Arbeit"]);

    const bea = await addAccount(port, ada.token, "bea");
    assert.equal((await request(port, "GET", `/v1/workspaces/${work.id}/changes`, undefined, bea.token)).status, 404);
  });
});

test("a workspace's look is the same for every device", async () => {
  await withServer(async (port) => {
    const ada = await openAccount(port);
    const work = JSON.parse(
      (await request(port, "POST", "/v1/workspaces", { name: "Arbeit" }, ada.token)).raw.toString("utf8"),
    ) as { id: string; updatedAt: string | null };
    assert.equal(work.updatedAt, null);

    const png = Buffer.from("not really a png");
    const digest = createHash("sha256").update(png).digest("hex");
    const missing = await request(port, "PATCH", `/v1/workspaces/${work.id}`, { icon: digest }, ada.token);
    assert.equal(missing.status, 400);
    assert.equal((JSON.parse(missing.raw.toString("utf8")) as { reason: string }).reason, "icon");

    const blob = await request(port, "PUT", `/v1/workspaces/${work.id}/blobs/${digest}`, png, ada.token);
    assert.equal(blob.status, 204);
    const styled = await request(
      port,
      "PATCH",
      `/v1/workspaces/${work.id}`,
      { name: "Büro", symbol: "briefcase.fill", icon: digest },
      ada.token,
    );
    assert.equal(styled.status, 200);
    const look = JSON.parse(styled.raw.toString("utf8")) as {
      name: string;
      symbol: string;
      icon: string;
      updatedAt: string;
    };
    assert.deepEqual([look.name, look.symbol, look.icon], ["Büro", "briefcase.fill", digest]);
    assert.ok(look.updatedAt);

    // The icon lies in that workspace's blobs, not in main's.
    const elsewhere = await request(port, "PATCH", "/v1/workspaces/main", { icon: digest }, ada.token);
    assert.equal(elsewhere.status, 400);

    const plain = await request(port, "PATCH", `/v1/workspaces/${work.id}`, { icon: null }, ada.token);
    const cleared = JSON.parse(plain.raw.toString("utf8")) as { name: string; symbol: string; icon: string | null };
    assert.deepEqual([cleared.name, cleared.symbol, cleared.icon], ["Büro", "briefcase.fill", null]);

    const main = await request(port, "PATCH", "/v1/workspaces/main", { symbol: "house" }, ada.token);
    const mainLook = JSON.parse(main.raw.toString("utf8")) as { name: string; symbol: string };
    assert.deepEqual([mainLook.name, mainLook.symbol], ["Privat", "house"]);

    for (const body of [{}, { symbol: "Not A Symbol" }, { symbol: 3 }, { icon: "abc" }, { name: "" }]) {
      assert.equal((await request(port, "PATCH", "/v1/workspaces/main", body, ada.token)).status, 400, JSON.stringify(body));
    }
    const unknown = "11111111-2222-4333-8444-555555555555";
    assert.equal((await request(port, "PATCH", `/v1/workspaces/${unknown}`, { symbol: "tray" }, ada.token)).status, 404);
  });
});

test("the order of workspaces is the account's, a device moves only those it names", async () => {
  await withServer(async (port) => {
    const ada = await openAccount(port);
    const ids: string[] = ["main"];
    for (const name of ["A", "B", "C"]) {
      const created = await request(port, "POST", "/v1/workspaces", { name }, ada.token);
      ids.push((JSON.parse(created.raw.toString("utf8")) as { id: string }).id);
    }
    const [main, a, b, c] = ids as [string, string, string, string];
    const order = async (): Promise<{ ids: string[]; ordered: boolean }> => {
      const listed = JSON.parse((await request(port, "GET", "/v1/workspaces", undefined, ada.token)).raw.toString("utf8")) as {
        workspaces: { id: string }[];
        ordered: boolean;
      };
      return { ids: listed.workspaces.map((workspace) => workspace.id), ordered: listed.ordered };
    };
    assert.deepEqual(await order(), { ids: [main, a, b, c], ordered: false });

    const moved = await request(port, "PUT", "/v1/workspace-order", { ids: [c, main, a, b] }, ada.token);
    assert.equal(moved.status, 200);
    assert.deepEqual(await order(), { ids: [c, main, a, b], ordered: true });

    // A device that has only main and b swaps them; c and a stay where they are.
    await request(port, "PUT", "/v1/workspace-order", { ids: [b, main] }, ada.token);
    assert.deepEqual((await order()).ids, [c, b, a, main]);

    const added = await request(port, "POST", "/v1/workspaces", { name: "D" }, ada.token);
    const d = (JSON.parse(added.raw.toString("utf8")) as { id: string }).id;
    assert.deepEqual((await order()).ids, [c, b, a, main, d]);

    for (const body of [{ ids: [a, a] }, { ids: ["11111111-2222-4333-8444-555555555555"] }, { ids: "main" }, {}]) {
      assert.equal((await request(port, "PUT", "/v1/workspace-order", body, ada.token)).status, 400, JSON.stringify(body));
    }
  });
});

test("a deleted workspace is gone for the account but kept on disk", async () => {
  await withServer(async (port, root) => {
    const ada = await openAccount(port);
    const ids: string[] = [];
    for (const name of ["A", "B"]) {
      const created = await request(port, "POST", "/v1/workspaces", { name }, ada.token);
      ids.push((JSON.parse(created.raw.toString("utf8")) as { id: string }).id);
    }
    const [a, b] = ids as [string, string];
    const noteId = "6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10";
    const put = await request(port, "PUT", `/v1/workspaces/${a}/notes/${noteId}`, { baseRevision: 0, note: textNote(noteId) }, ada.token);
    assert.equal(put.status, 201);
    await request(port, "PUT", "/v1/workspace-order", { ids: [b, a, "main"] }, ada.token);

    const bea = await addAccount(port, ada.token, "bea");
    assert.equal((await request(port, "DELETE", `/v1/workspaces/${a}`, undefined, bea.token)).status, 404);

    const deleted = await request(port, "DELETE", `/v1/workspaces/${a}`, undefined, ada.token);
    assert.equal(deleted.status, 204);
    const listed = JSON.parse((await request(port, "GET", "/v1/workspaces", undefined, ada.token)).raw.toString("utf8")) as {
      workspaces: { id: string }[];
    };
    assert.deepEqual(listed.workspaces.map((workspace) => workspace.id), [b, "main"]);
    assert.equal((await request(port, "GET", `/v1/workspaces/${a}/changes`, undefined, ada.token)).status, 404);
    assert.equal((await request(port, "DELETE", `/v1/workspaces/${a}`, undefined, ada.token)).status, 404);

    const spaces = join(root, "spaces", ada.account.id);
    const kept = readdirSync(join(spaces, "deleted"));
    assert.equal(kept.length, 1);
    assert.ok(kept[0]?.startsWith(`${a}-`));
    assert.ok(readdirSync(join(spaces, "deleted", kept[0] ?? "", "notes")).length > 0);
  });
});

test("main can be deleted too, as long as one workspace stays", async () => {
  await withServer(async (port, root) => {
    const ada = await openAccount(port);
    const noteId = "6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10";
    assert.equal((await request(port, "PUT", `/v1/notes/${noteId}`, { baseRevision: 0, note: textNote(noteId) }, ada.token)).status, 201);

    const alone = await request(port, "DELETE", "/v1/workspaces/main", undefined, ada.token);
    assert.equal(alone.status, 400);
    assert.equal((JSON.parse(alone.raw.toString("utf8")) as { reason: string }).reason, "last workspace");

    const created = await request(port, "POST", "/v1/workspaces", { name: "Arbeit" }, ada.token);
    const work = (JSON.parse(created.raw.toString("utf8")) as { id: string }).id;
    assert.equal((await request(port, "DELETE", "/v1/workspaces/main", undefined, ada.token)).status, 204);

    const listed = JSON.parse((await request(port, "GET", "/v1/workspaces", undefined, ada.token)).raw.toString("utf8")) as {
      workspaces: { id: string }[];
    };
    assert.deepEqual(listed.workspaces.map((workspace) => workspace.id), [work]);
    for (const path of ["/v1/changes", `/v1/notes/${noteId}`, "/v1/workspaces/main/changes"]) {
      assert.equal((await request(port, "GET", path, undefined, ada.token)).status, 404, path);
    }
    assert.equal((await request(port, "PATCH", "/v1/workspaces/main", { symbol: "house" }, ada.token)).status, 404);
    assert.equal((await request(port, "DELETE", `/v1/workspaces/${work}`, undefined, ada.token)).status, 400);

    const kept = readdirSync(join(root, "spaces", ada.account.id, "deleted"));
    assert.equal(kept.length, 1);
    assert.ok(kept[0]?.startsWith("main-"));
    assert.deepEqual(readdirSync(join(root, "spaces", ada.account.id, "deleted", kept[0] ?? "", "notes")), [`${noteId}.json`]);

    // A restart opens every store again; main stays deleted.
    const again = new Accounts(root, 1_000, "test-token");
    assert.deepEqual(again.workspaces(ada.account.id).workspaces.map((workspace) => workspace.id), [work]);
  });
});

test("the admin renames, promotes, sets passwords and deletes accounts; the last admin stays", async () => {
  await withServer(async (port, root) => {
    const ada = await openAccount(port);
    const bea = await addAccount(port, ada.token, "bea");
    const listed = JSON.parse((await request(port, "GET", "/v1/accounts", undefined, ada.token)).raw.toString("utf8")) as {
      me: string;
    };
    assert.equal(listed.me, ada.account.id);

    // Only the admin may.
    assert.equal((await request(port, "PATCH", `/v1/accounts/${ada.account.id}`, { admin: false }, bea.token)).status, 403);
    assert.equal((await request(port, "DELETE", `/v1/accounts/${ada.account.id}`, undefined, bea.token)).status, 403);

    // The last admin keeps the role and the account.
    const demote = await request(port, "PATCH", `/v1/accounts/${ada.account.id}`, { admin: false }, ada.token);
    assert.equal(demote.status, 400);
    assert.equal((JSON.parse(demote.raw.toString("utf8")) as { reason: string }).reason, "last admin");
    assert.equal((await request(port, "DELETE", `/v1/accounts/${ada.account.id}`, undefined, ada.token)).status, 400);

    // Rename: the old name is free, the session goes on, the new name signs in.
    const renamed = await request(port, "PATCH", `/v1/accounts/${bea.account.id}`, { name: "Beatrix" }, ada.token);
    assert.equal(renamed.status, 200);
    assert.equal((JSON.parse(renamed.raw.toString("utf8")) as { name: string }).name, "beatrix");
    assert.equal((await request(port, "GET", "/v1/workspaces", undefined, bea.token)).status, 200);
    assert.equal((await request(port, "POST", "/v1/session", { name: "bea", password: "secretsecret" }, null)).status, 401);
    assert.equal((await request(port, "POST", "/v1/session", { name: "beatrix", password: "secretsecret" }, null)).status, 200);
    await addAccount(port, ada.token, "cem");
    const cem = JSON.parse((await request(port, "GET", "/v1/accounts", undefined, ada.token)).raw.toString("utf8")) as {
      accounts: { id: string; name: string }[];
    };
    const cemId = cem.accounts.find((account) => account.name === "cem")?.id ?? "";
    assert.equal((await request(port, "PATCH", `/v1/accounts/${cemId}`, { name: "beatrix" }, ada.token)).status, 409);

    // A new password ends the account's sessions.
    const reset = await request(port, "PATCH", `/v1/accounts/${bea.account.id}`, { password: "neuesneues" }, ada.token);
    assert.equal(reset.status, 200);
    assert.equal((await request(port, "GET", "/v1/workspaces", undefined, bea.token)).status, 401);
    assert.equal((await request(port, "POST", "/v1/session", { name: "beatrix", password: "neuesneues" }, null)).status, 200);

    // Its own new password keeps the admin's session.
    assert.equal((await request(port, "PATCH", `/v1/accounts/${ada.account.id}`, { password: "adminadmin" }, ada.token)).status, 200);
    assert.equal((await request(port, "GET", "/v1/accounts", undefined, ada.token)).status, 200);

    // A second admin, then the first one may go, even by itself.
    const promoted = await request(port, "PATCH", `/v1/accounts/${bea.account.id}`, { admin: true }, ada.token);
    assert.equal((JSON.parse(promoted.raw.toString("utf8")) as { admin: boolean }).admin, true);
    const again = await request(port, "POST", "/v1/session", { name: "beatrix", password: "neuesneues" }, null);
    const beaToken = (JSON.parse(again.raw.toString("utf8")) as Opened).token;
    const noteId = "6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10";
    await request(port, "PUT", `/v1/notes/${noteId}`, { baseRevision: 0, note: textNote(noteId) }, ada.token);
    assert.equal((await request(port, "DELETE", `/v1/accounts/${ada.account.id}`, undefined, ada.token)).status, 204);
    assert.equal((await request(port, "GET", "/v1/workspaces", undefined, ada.token)).status, 401);
    assert.equal((await request(port, "POST", "/v1/session", { name: "ada", password: "adminadmin" }, null)).status, 401);
    const left = JSON.parse((await request(port, "GET", "/v1/accounts", undefined, beaToken)).raw.toString("utf8")) as {
      accounts: { name: string }[];
    };
    assert.deepEqual(left.accounts.map((account) => account.name), ["beatrix", "cem"]);

    // Kept on disk, with its identity, for the admin to bring back by hand.
    const kept = readdirSync(join(root, "deleted-accounts"));
    assert.equal(kept.length, 1);
    const folder = join(root, "deleted-accounts", kept[0] ?? "");
    assert.equal((JSON.parse(readFileSync(join(folder, "identity.json"), "utf8")) as { name: string }).name, "ada");
    assert.deepEqual(readdirSync(join(folder, "notes")), [`${noteId}.json`]);
    assert.equal((await request(port, "DELETE", `/v1/accounts/${ada.account.id}`, undefined, beaToken)).status, 404);
  });
});

test("an account has at most 50 workspaces, main included", async () => {
  await withServer(async (port) => {
    const ada = await openAccount(port);
    for (let index = 2; index <= 50; index += 1) {
      const created = await request(port, "POST", "/v1/workspaces", { name: `W${index}` }, ada.token);
      assert.equal(created.status, 201, `workspace ${index}`);
    }
    const tooMany = await request(port, "POST", "/v1/workspaces", { name: "W51" }, ada.token);
    assert.equal(tooMany.status, 400);
    const listed = await request(port, "GET", "/v1/workspaces", undefined, ada.token);
    assert.equal((JSON.parse(listed.raw.toString("utf8")) as { workspaces: unknown[] }).workspaces.length, 50);
  });
});

/** A login as a client behind a proxy would send it. */
async function loginFrom(port: number, name: string, forwardedFor?: string): Promise<number> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (forwardedFor !== undefined) headers["X-Forwarded-For"] = forwardedFor;
  const response = await fetch(`http://127.0.0.1:${port}/v1/session`, {
    method: "POST",
    headers,
    body: JSON.stringify({ name, password: "wrongwrong" }),
  });
  await response.arrayBuffer();
  return response.status;
}

test("JSON needs its content type, and open routes take small bodies", async () => {
  await withServer(async (port) => {
    const plain = await fetch(`http://127.0.0.1:${port}/v1/session`, {
      method: "POST",
      headers: { "Content-Type": "text/plain" },
      body: JSON.stringify({ name: "ada", password: "secretsecret" }),
    });
    assert.equal(plain.status, 415);
    assert.equal(((await plain.json()) as { error: string }).error, "unsupported-media-type");
    const large = await request(port, "POST", "/v1/session", { name: "ada", password: "x".repeat(20_000) }, null);
    assert.equal(large.status, 413);
    const ada = await openAccount(port);
    const named = await request(port, "POST", "/v1/workspaces", { name: "Arbeit", pad: "x".repeat(20_000) }, ada.token);
    assert.equal(named.status, 201);
  });
});

test("a trusted proxy names the client, others share the proxy's counter", async () => {
  await withServer(
    async (port) => {
      for (let attempt = 0; attempt < CLIENT_LOCK_AFTER; attempt += 1) {
        // What the client claims on the left does not count; the proxy appended the real address.
        assert.equal(await loginFrom(port, `guess${attempt}`, `198.51.100.${attempt}, 203.0.113.5`), 401);
      }
      assert.equal(await loginFrom(port, "someone", "203.0.113.5"), 429);
      assert.equal(await loginFrom(port, "someone", "203.0.113.6"), 401);
    },
    { trustedProxies: trustedProxies("127.0.0.1, ::1") },
  );
  await withServer(async (port) => {
    for (let attempt = 0; attempt < CLIENT_LOCK_AFTER; attempt += 1) {
      assert.equal(await loginFrom(port, `guess${attempt}`, `203.0.113.${attempt}`), 401);
    }
    assert.equal(await loginFrom(port, "someone", "203.0.113.200"), 429);
  });
});

test("trusted proxies are addresses or networks", () => {
  assert.equal(trustedProxies(undefined), null);
  assert.equal(trustedProxies(" "), null);
  const list = trustedProxies("10.0.0.0/8, ::1");
  assert.ok(list?.check("10.1.2.3", "ipv4"));
  assert.ok(!list?.check("11.0.0.1", "ipv4"));
  assert.ok(list?.check("::1", "ipv6"));
  assert.throws(() => trustedProxies("localhost"), /not an address/);
  assert.throws(() => trustedProxies("10.0.0.0/33"), /not an address/);
});

test("failures count per IPv4 address and per IPv6 /64", () => {
  assert.equal(clientKey("203.0.113.5"), "203.0.113.5");
  assert.equal(clientKey("::ffff:203.0.113.5"), "203.0.113.5");
  assert.equal(clientKey("2001:db8:1:2:aaaa::1"), "2001:db8:1:2::/64");
  assert.equal(clientKey("2001:0db8:0001:0002:ffff:ffff:ffff:ffff"), "2001:db8:1:2::/64");
  assert.equal(clientKey("2001:db8::1"), "2001:db8:0:0::/64");
  assert.equal(clientKey("fe80::1%eth0"), "fe80:0:0:0::/64");
  assert.equal(clientKey("64:ff9b::192.0.2.1"), "64:ff9b:0:0::/64");
  assert.equal(clientKey("::1"), "0:0:0:0::/64");
});

test("password checks running at once are bounded", async () => {
  const root = mkdtempSync(join(tmpdir(), "inkhash-"));
  try {
    const accounts = new Accounts(root, 1_000, "test-token");
    const status = (attempt: Promise<unknown>) =>
      attempt.then(
        () => 200,
        (error: unknown) => (error instanceof StoreError ? error.status : 500),
      );
    const wrong = { name: "ada", password: "wrongwrong" };
    const one = await Promise.all(
      Array.from({ length: MAX_HASHING_PER_CLIENT + 1 }, () => status(accounts.login(wrong, "203.0.113.5"))),
    );
    assert.deepEqual(one, [...Array<number>(MAX_HASHING_PER_CLIENT).fill(401), 429]);
    const many = await Promise.all(
      Array.from({ length: MAX_HASHING + 1 }, (_, index) =>
        status(accounts.login({ name: `n${index}`, password: "wrongwrong" }, `198.51.100.${index}`)),
      ),
    );
    assert.deepEqual(many, [...Array<number>(MAX_HASHING).fill(401), 429]);
    // Once they are done, there is room again.
    assert.equal(await status(accounts.login(wrong, "192.0.2.1")), 401);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("data files are private to the server", async () => {
  await withServer(async (port, root) => {
    const ada = await openAccount(port);
    const id = "6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10";
    assert.equal((await request(port, "PUT", `/v1/notes/${id}`, { baseRevision: 0, note: textNote(id) }, ada.token)).status, 201);
    const mode = (path: string) => statSync(path).mode & 0o777;
    assert.equal(mode(join(root, "identities", "ada.json")), 0o600);
    assert.equal(mode(join(root, "sessions")), 0o700);
    const space = join(root, "spaces", ada.account.id);
    assert.equal(mode(space), 0o700);
    assert.equal(mode(join(space, "notes", `${id}.json`)), 0o600);
    assert.equal(mode(join(space, "changes.jsonl")), 0o600);
  });
});
