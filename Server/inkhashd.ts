/** inkhash API. One process, one directory, no other responsibilities. */

import { readFileSync } from "node:fs";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { BlockList, isIP } from "node:net";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

import { Accounts, MAIN_WORKSPACE } from "./accounts.js";
import { ADMIN_CSP, ADMIN_HTML } from "./admin/page.js";
import { DEFAULT_CHANGE_LIMIT, StoreError, type Store } from "./store.js";

const SWEEP_MS = 6 * 60 * 60 * 1000;

export interface ServeOptions {
  maxJson?: number;
  maxBlob?: number;
  /** Body limit for routes without a session: setup and login. */
  maxOpenJson?: number;
  /** Proxies whose `X-Forwarded-For` names the client. See ADR 0038. */
  trustedProxies?: BlockList | null;
}

interface Limits {
  maxJson: number;
  maxBlob: number;
  maxOpenJson: number;
}

type Reply =
  | { status: number; json: unknown }
  | { status: number; bytes: Buffer; type: string; headers?: Record<string, string> }
  | { status: 204 };

interface Context {
  req: IncomingMessage;
  url: URL;
  params: string[];
  accounts: Accounts;
  client: string;
  token: string;
  accountId: string | null;
  workspace: string;
  limits: Limits;
}

interface Route {
  method: string;
  pattern: RegExp;
  /** `session` needs a valid session, `open` ignores it. */
  access: "open" | "session";
  handle: (ctx: Context) => Reply | Promise<Reply>;
}

/** `INKHASH_TRUSTED_PROXIES`: addresses and networks, separated by commas. Null when empty. */
export function trustedProxies(value: string | undefined): BlockList | null {
  const entries = (value ?? "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
  if (entries.length === 0) return null;
  const list = new BlockList();
  for (const entry of entries) {
    const [address = "", bits, extra] = entry.split("/");
    const family = isIP(address);
    const prefix = Number(bits);
    const maxBits = family === 6 ? 128 : 32;
    if (family === 0 || extra !== undefined || (bits !== undefined && !(/^\d+$/.test(bits) && prefix <= maxBits))) {
      throw new Error(`INKHASH_TRUSTED_PROXIES: not an address or network: ${entry}`);
    }
    const type = family === 6 ? "ipv6" : "ipv4";
    if (bits === undefined) list.addAddress(address, type);
    else list.addSubnet(address, prefix, type);
  }
  return list;
}

function unmapped(address: string): string {
  return /^::ffff:\d{1,3}(\.\d{1,3}){3}$/i.test(address) ? address.slice(7) : address;
}

function trusted(list: BlockList, address: string): boolean {
  const family = isIP(address);
  return family !== 0 && list.check(address, family === 6 ? "ipv6" : "ipv4");
}

let warnedForwarded = false;

/**
 * The client's address. Behind a trusted proxy it is the rightmost entry of `X-Forwarded-For`
 * that is not a trusted proxy itself: entries further left are whatever the client claimed.
 */
export function clientAddress(req: IncomingMessage, proxies: BlockList | null): string {
  const peer = unmapped(req.socket.remoteAddress ?? "unknown");
  const header = req.headers["x-forwarded-for"];
  if (header === undefined) return peer;
  if (proxies === null || !trusted(proxies, peer)) {
    if (!warnedForwarded) {
      warnedForwarded = true;
      process.stderr.write(
        `${peer} sends X-Forwarded-For but is not in INKHASH_TRUSTED_PROXIES; clients behind it share one throttle\n`,
      );
    }
    return peer;
  }
  const hops = (Array.isArray(header) ? header.join(",") : header)
    .split(",")
    .map((hop) => unmapped(hop.trim()))
    .filter(Boolean);
  for (let index = hops.length - 1; index >= 0; index -= 1) {
    const hop = hops[index] ?? "";
    if (isIP(hop) === 0) return peer;
    if (!trusted(proxies, hop)) return hop;
  }
  return hops[0] ?? peer;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function bearer(req: IncomingMessage): string {
  const header = req.headers.authorization ?? "";
  return header.startsWith("Bearer ") ? header.slice(7) : "";
}

async function readBody(req: IncomingMessage, limit: number): Promise<Buffer> {
  const declared = req.headers["content-length"];
  if (declared !== undefined) {
    if (!/^\d+$/.test(declared)) throw new StoreError(400, "bad-request", { reason: "short body" });
    if (Number(declared) > limit) throw new StoreError(413, "too-large");
  }
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of req) {
    const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    total += buf.length;
    if (total > limit) throw new StoreError(413, "too-large");
    chunks.push(buf);
  }
  if (declared !== undefined && total !== Number(declared)) {
    throw new StoreError(400, "bad-request", { reason: "short body" });
  }
  return Buffer.concat(chunks);
}

/** JSON only as `application/json`: a browser cannot send that cross-site without a preflight. */
async function readJson(ctx: Context): Promise<unknown> {
  const type = (ctx.req.headers["content-type"] ?? "").split(";")[0]?.trim().toLowerCase();
  if (type !== "application/json") throw new StoreError(415, "unsupported-media-type");
  const limit = ctx.accountId === null ? ctx.limits.maxOpenJson : ctx.limits.maxJson;
  const text = (await readBody(ctx.req, limit)).toString("utf8");
  try {
    return JSON.parse(text || "{}") as unknown;
  } catch {
    throw new StoreError(400, "bad-request", { reason: "json" });
  }
}

function queryInt(value: string | null): number {
  if (value == null || !/^-?\d+$/.test(value)) throw new StoreError(400, "bad-request");
  return Number(value);
}

function accountOf(ctx: Context): string {
  if (ctx.accountId === null) throw new StoreError(401, "unauthorized");
  return ctx.accountId;
}

/** Note routes exist twice: under `/v1/workspaces/{ws}` and, for `main`, without the prefix. */
function storeOf(ctx: Context): Store {
  return ctx.accounts.workspaceStore(accountOf(ctx), ctx.workspace);
}

function json(status: number, payload: unknown): Reply {
  return { status, json: payload };
}

let adminScript: Buffer | null = null;

/** Compiled next to this file by `tsc`, read once. */
function adminClient(): Buffer {
  adminScript ??= readFileSync(new URL("./admin/client.js", import.meta.url));
  return adminScript;
}

const ADMIN_HEADERS = {
  "Content-Security-Policy": ADMIN_CSP,
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
  "X-Frame-Options": "DENY",
};

const ROUTES: Route[] = [
  {
    method: "GET",
    pattern: /^\/v1\/health$/,
    access: "open",
    handle: (ctx) => json(200, { ok: true, registration: ctx.accounts.registration(), version: serverVersion(), vault: true }),
  },
  {
    method: "POST",
    pattern: /^\/v1\/setup$/,
    access: "open",
    handle: async (ctx) => json(201, await ctx.accounts.setup(await readJson(ctx), ctx.client)),
  },
  {
    method: "GET",
    pattern: /^\/v1\/accounts$/,
    access: "session",
    handle: (ctx) => json(200, { accounts: ctx.accounts.listAccounts(accountOf(ctx)), me: accountOf(ctx) }),
  },
  {
    method: "POST",
    pattern: /^\/v1\/accounts$/,
    access: "session",
    handle: async (ctx) => json(201, await ctx.accounts.createAccount(accountOf(ctx), await readJson(ctx))),
  },
  {
    method: "PATCH",
    pattern: /^\/v1\/accounts\/([^/]+)$/,
    access: "session",
    handle: async (ctx) =>
      json(200, await ctx.accounts.updateAccount(accountOf(ctx), ctx.params[0] ?? "", await readJson(ctx), ctx.token)),
  },
  {
    method: "DELETE",
    pattern: /^\/v1\/accounts\/([^/]+)$/,
    access: "session",
    handle: (ctx) => {
      ctx.accounts.deleteAccount(accountOf(ctx), ctx.params[0] ?? "");
      return { status: 204 };
    },
  },
  {
    method: "GET",
    pattern: /^\/v1\/vault$/,
    access: "session",
    handle: (ctx) => {
      const vault = ctx.accounts.vault(accountOf(ctx));
      if (!vault) throw new StoreError(404, "no-vault");
      return json(200, vault);
    },
  },
  {
    method: "PUT",
    pattern: /^\/v1\/vault$/,
    access: "session",
    handle: async (ctx) => {
      const [status, vault] = ctx.accounts.putVault(accountOf(ctx), await readJson(ctx));
      return json(status, vault);
    },
  },
  {
    method: "DELETE",
    pattern: /^\/v1\/vault$/,
    access: "session",
    handle: async (ctx) => {
      await ctx.accounts.resetVault(accountOf(ctx), await readJson(ctx), ctx.client);
      return { status: 204 };
    },
  },
  {
    method: "PUT",
    pattern: /^\/v1\/password$/,
    access: "session",
    handle: async (ctx) => {
      await ctx.accounts.changePassword(accountOf(ctx), await readJson(ctx), ctx.token, ctx.client);
      return { status: 204 };
    },
  },
  {
    method: "POST",
    pattern: /^\/v1\/session$/,
    access: "open",
    handle: async (ctx) => json(200, await ctx.accounts.login(await readJson(ctx), ctx.client)),
  },
  {
    method: "DELETE",
    pattern: /^\/v1\/session$/,
    access: "session",
    handle: (ctx) => {
      ctx.accounts.logout(ctx.token);
      return { status: 204 };
    },
  },
  {
    method: "GET",
    pattern: /^\/v1\/workspaces$/,
    access: "session",
    handle: (ctx) => json(200, ctx.accounts.workspaces(accountOf(ctx))),
  },
  {
    method: "POST",
    pattern: /^\/v1\/workspaces$/,
    access: "session",
    handle: async (ctx) => json(201, ctx.accounts.createWorkspace(accountOf(ctx), await readJson(ctx))),
  },
  {
    method: "PATCH",
    pattern: /^\/v1\/workspaces\/([^/]+)$/,
    access: "session",
    handle: async (ctx) =>
      json(200, ctx.accounts.updateWorkspace(accountOf(ctx), ctx.params[0] ?? "", await readJson(ctx))),
  },
  {
    method: "DELETE",
    pattern: /^\/v1\/workspaces\/([^/]+)$/,
    access: "session",
    handle: (ctx) => {
      ctx.accounts.deleteWorkspace(accountOf(ctx), ctx.params[0] ?? "");
      return { status: 204 };
    },
  },
  {
    method: "PUT",
    pattern: /^\/v1\/workspace-order$/,
    access: "session",
    handle: async (ctx) => json(200, ctx.accounts.orderWorkspaces(accountOf(ctx), await readJson(ctx))),
  },
  {
    method: "GET",
    pattern: /^\/v1\/changes$/,
    access: "session",
    handle: (ctx) => {
      const after = queryInt(ctx.url.searchParams.get("after") ?? "0");
      const limitRaw = ctx.url.searchParams.get("limit");
      const limit = limitRaw === null ? DEFAULT_CHANGE_LIMIT : queryInt(limitRaw);
      return json(200, storeOf(ctx).changes(after, limit));
    },
  },
  {
    method: "GET",
    pattern: /^\/v1\/notes\/([^/]+)$/,
    access: "session",
    handle: (ctx) => json(200, storeOf(ctx).getNote(ctx.params[0] ?? "")),
  },
  {
    method: "PUT",
    pattern: /^\/v1\/notes\/([^/]+)$/,
    access: "session",
    handle: async (ctx) => {
      const store = storeOf(ctx);
      const payload = await readJson(ctx);
      if (!isRecord(payload)) throw new StoreError(400, "bad-request");
      const base = payload.baseRevision;
      if (typeof base !== "number" || !Number.isInteger(base)) throw new StoreError(400, "bad-request");
      const [status, note] = store.putNote(ctx.params[0] ?? "", base, payload.note);
      return json(status, note);
    },
  },
  {
    method: "DELETE",
    pattern: /^\/v1\/notes\/([^/]+)$/,
    access: "session",
    handle: (ctx) => {
      const base = queryInt(ctx.url.searchParams.get("baseRevision"));
      return json(200, storeOf(ctx).deleteNote(ctx.params[0] ?? "", base));
    },
  },
  {
    method: "PUT",
    pattern: /^\/v1\/blobs\/([^/]+)$/,
    access: "session",
    handle: async (ctx) => {
      const store = storeOf(ctx);
      store.putBlob(ctx.params[0] ?? "", await readBody(ctx.req, ctx.limits.maxBlob));
      return { status: 204 };
    },
  },
  {
    method: "GET",
    pattern: /^\/v1\/blobs\/([^/]+)$/,
    access: "session",
    handle: (ctx) => ({
      status: 200,
      bytes: storeOf(ctx).getBlob(ctx.params[0] ?? ""),
      type: "application/octet-stream",
    }),
  },
  {
    method: "GET",
    pattern: /^\/admin\/?$/,
    access: "open",
    handle: () => ({
      status: 200,
      bytes: Buffer.from(ADMIN_HTML),
      type: "text/html; charset=utf-8",
      headers: ADMIN_HEADERS,
    }),
  },
  {
    method: "GET",
    pattern: /^\/admin\/client\.js$/,
    access: "open",
    handle: () => ({
      status: 200,
      bytes: adminClient(),
      type: "text/javascript; charset=utf-8",
      headers: { "Cache-Control": "no-cache" },
    }),
  },
];

function reply(req: IncomingMessage, res: ServerResponse, answer: Reply): void {
  let body: Buffer = Buffer.alloc(0);
  let type = "application/json";
  let extra: Record<string, string> = {};
  if ("bytes" in answer) {
    body = answer.bytes;
    type = answer.type;
    extra = answer.headers ?? {};
  } else if ("json" in answer) {
    body = Buffer.from(JSON.stringify(answer.json));
    type = "application/json; charset=utf-8";
  }
  const headers: Record<string, string | number> = {
    "Content-Type": type,
    "Content-Length": body.length,
    "X-Content-Type-Options": "nosniff",
    Server: "inkhash",
    ...extra,
  };
  // An unread request body would be parsed as the next request on a kept-alive connection.
  if (!req.complete) headers.Connection = "close";
  res.writeHead(answer.status, headers);
  res.end(body);
}

async function route(
  req: IncomingMessage,
  res: ServerResponse,
  accounts: Accounts,
  limits: Limits,
  proxies: BlockList | null,
): Promise<void> {
  const method = req.method ?? "GET";
  const url = new URL(req.url ?? "/", "http://127.0.0.1");
  process.stderr.write(`${method} ${url.pathname}\n`);
  let client = "unknown";
  try {
    // `/v1/workspaces/{ws}/notes/...` is the note route for that workspace.
    let workspace = MAIN_WORKSPACE;
    let path = url.pathname;
    const scoped = /^\/v1\/workspaces\/([^/]+)(\/(?:changes|notes\/[^/]+|blobs\/[^/]+))$/.exec(path);
    if (scoped) {
      workspace = (scoped[1] ?? "").toLowerCase();
      path = `/v1${scoped[2] ?? ""}`;
    }
    let params: string[] | null = null;
    let found: Route | null = null;
    let pathKnown = false;
    for (const candidate of ROUTES) {
      const match = candidate.pattern.exec(path);
      if (!match) continue;
      pathKnown = true;
      if (candidate.method !== method) continue;
      found = candidate;
      params = match.slice(1);
      break;
    }
    if (!found || !params) {
      reply(req, res, pathKnown ? json(405, { error: "method-not-allowed" }) : json(404, { error: "not-found" }));
      return;
    }
    client = clientAddress(req, proxies);
    const token = bearer(req);
    const accountId = found.access === "open" ? null : accounts.accountId(token);
    if (found.access === "session" && accountId === null) {
      reply(req, res, json(401, { error: "unauthorized" }));
      return;
    }
    const ctx: Context = {
      req,
      url,
      params,
      accounts,
      client,
      token,
      accountId,
      workspace,
      limits,
    };
    reply(req, res, await found.handle(ctx));
  } catch (error) {
    if (error instanceof StoreError) {
      // For fail2ban. Never the name, the password or a token, see P-017.
      const signIn = /^\/v1\/(setup|session)$/.test(url.pathname) && method === "POST" && (error.status === 401 || error.status === 429);
      const passwordChange =
        ((url.pathname === "/v1/password" && method === "PUT") || (url.pathname === "/v1/vault" && method === "DELETE")) &&
        (error.status === 403 || error.status === 429);
      if (signIn || passwordChange) {
        process.stderr.write(`auth failed ${url.pathname} ${error.status} from ${client}\n`);
      }
      reply(req, res, json(error.status, { error: error.code, ...error.extra }));
      return;
    }
    process.stderr.write(`${error instanceof Error ? error.stack : String(error)}\n`);
    reply(req, res, json(500, { error: "internal" }));
  }
}

export function serve(accounts: Accounts, options: ServeOptions = {}): Server {
  const limits: Limits = {
    maxJson: options.maxJson ?? 2 * 1024 * 1024,
    maxBlob: options.maxBlob ?? 20 * 1024 * 1024,
    maxOpenJson: options.maxOpenJson ?? 16 * 1024,
  };
  const proxies = options.trustedProxies ?? null;
  return createServer((req, res) => {
    void route(req, res, accounts, limits, proxies);
  });
}

/** Where to open the admin page, as far as the server can tell from its own address. */
export function adminAddress(host: string, port: number): string {
  if (host === "0.0.0.0" || host === "::") return `http://<this host>:${port}/admin`;
  return `http://${host.includes(":") ? `[${host}]` : host}:${port}/admin`;
}

let cachedVersion: string | undefined;

/** From `package.json` next to `dist/`. Releases set it, see ADR 0039. Read once. */
export function serverVersion(): string {
  if (cachedVersion !== undefined) return cachedVersion;
  try {
    const parsed = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8")) as { version?: unknown };
    cachedVersion = typeof parsed.version === "string" ? parsed.version : "dev";
  } catch {
    cachedVersion = "dev";
  }
  return cachedVersion;
}

/** The data directory is not writable, usually a Docker volume that belongs to root. See P-023. */
function openAccounts(root: string): Accounts {
  try {
    return new Accounts(root);
  } catch (error) {
    if (error instanceof Error && "code" in error && (error.code === "EACCES" || error.code === "EPERM")) {
      const user = process.getuid?.() ?? "?";
      process.stderr.write(`cannot write ${root} as uid ${user}: ${error.message}\nsee docs/DEPLOY.md, data directory\n`);
      process.exit(1);
    }
    throw error;
  }
}

export function main(): void {
  const host = process.env.INKHASH_HOST ?? "127.0.0.1";
  const port = Number(process.env.INKHASH_PORT ?? "8787");
  const root = process.env.INKHASH_DATA ?? "/data";
  if (process.env.INKHASH_TOKEN) {
    process.stderr.write("INKHASH_TOKEN is no longer used; the server makes its own setup token (ADR 0021)\n");
  }
  const proxies = trustedProxies(process.env.INKHASH_TRUSTED_PROXIES);
  const accounts = openAccounts(root);
  const server = serve(accounts, { trustedProxies: proxies });
  const sweeper = setInterval(() => {
    try {
      accounts.sweep();
    } catch (error) {
      process.stderr.write(`sweep failed: ${error instanceof Error ? error.message : String(error)}\n`);
    }
  }, SWEEP_MS);
  sweeper.unref();

  // Writes are synchronous, so no request is ever half written when a signal arrives.
  const stop = (signal: string) => {
    process.stderr.write(`${signal}, closing\n`);
    clearInterval(sweeper);
    server.close(() => process.exit(0));
    server.closeIdleConnections();
    setTimeout(() => process.exit(0), 5_000).unref();
  };
  process.once("SIGTERM", () => stop("SIGTERM"));
  process.once("SIGINT", () => stop("SIGINT"));

  server.listen(port, host, () => {
    process.stderr.write(`inkhash ${serverVersion()} ${host}:${port}\n`);
    if (proxies) process.stderr.write(`trusted proxies: ${process.env.INKHASH_TRUSTED_PROXIES}\n`);
    // The one token that is logged on purpose: it only creates the admin and dies with that. See ADR 0021.
    const setupToken = accounts.setupToken;
    if (setupToken) {
      process.stderr.write(`not set up yet: open ${adminAddress(host, port)}\nsetup token: ${setupToken}\n`);
    }
  });
}

const invoked = process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
if (invoked) main();
