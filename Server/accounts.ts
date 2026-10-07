/** Accounts and sessions. Notes stay in a Store per account. */

import { pbkdf2, randomBytes, randomUUID, timingSafeEqual, createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync, renameSync, rmSync, mkdirSync } from "node:fs";
import { isIPv6 } from "node:net";
import { join } from "node:path";
import { promisify } from "node:util";

import { DIR_MODE, Store, StoreError, atomicWrite, canonicalId, nowStamp } from "./store.js";

const pbkdf2Async = promisify(pbkdf2);

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const NAME_RE = /^[a-z0-9][a-z0-9._-]{0,30}[a-z0-9]$/;
const MIN_PASSWORD = 8;
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

export const DEFAULT_ROUNDS = 600_000;
export const NAME_LOCK_AFTER = 8;
export const CLIENT_LOCK_AFTER = 30;
/** Password checks running at once, in all and per client key. See ADR 0038. */
export const MAX_HASHING = 16;
export const MAX_HASHING_PER_CLIENT = 2;
const LOCK_MS = 15 * 60 * 1000;
export const SESSION_IDLE_DAYS = 90;
const SESSION_TOUCH_MS = DAY;
const THROTTLE_KEYS = 10_000;
export const MAIN_WORKSPACE = "main";
const DEFAULT_MAIN_NAME = "Privat";
const MAX_WORKSPACES = 50;
const MAX_WORKSPACE_NAME = 40;

/** How a workspace looks in the apps, the same on every device. See ADR 0043. */
export interface Workspace {
  id: string;
  name: string;
  /** SF Symbol name. Null until a device sets the look. */
  symbol: string | null;
  /** sha256 of a PNG in the workspace's own blobs, shown instead of the symbol. */
  icon: string | null;
  /** Last change of name, symbol or icon. Null while no device has set them. */
  updatedAt: string | null;
}

export interface WorkspaceList {
  workspaces: Workspace[];
  /** Whether the account has stored an order. Until then `main` comes first, the rest by creation. */
  ordered: boolean;
}

/** What `workspaces.json` and `main.json` hold besides the id. */
interface Look {
  name?: string;
  symbol?: string;
  icon?: string;
  updatedAt?: string;
}

const SYMBOL_RE = /^[a-z0-9]+(\.[a-z0-9]+)*$/;
const MAX_SYMBOL = 64;
const SHA_RE = /^[0-9a-f]{64}$/;

function workspaceName(value: unknown): string {
  if (typeof value !== "string") throw new StoreError(400, "bad-request", { reason: "name" });
  const name = value.trim();
  if (name.length < 1 || name.length > MAX_WORKSPACE_NAME || [...name].some((ch) => (ch.codePointAt(0) ?? 0) < 32)) {
    throw new StoreError(400, "bad-request", { reason: "name" });
  }
  return name;
}

interface StoredWorkspace extends Look {
  id: string;
  name: string;
}

function lookOf(item: Record<string, unknown>): Look {
  const look: Look = {};
  if (typeof item.symbol === "string") look.symbol = item.symbol;
  if (typeof item.icon === "string") look.icon = item.icon;
  if (typeof item.updatedAt === "string") look.updatedAt = item.updatedAt;
  return look;
}

function toWorkspace(stored: StoredWorkspace): Workspace {
  return {
    id: stored.id,
    name: stored.name,
    symbol: stored.symbol ?? null,
    icon: stored.icon ?? null,
    updatedAt: stored.updatedAt ?? null,
  };
}

interface Identity {
  id: string;
  name: string;
  passwordHash: string;
  createdAt: string;
  /** The one account that may create others. See ADR 0021. */
  admin?: boolean;
}

export interface AccountSummary {
  id: string;
  name: string;
  admin: boolean;
  createdAt: string;
}

interface SessionRecord {
  accountId?: unknown;
  createdAt?: unknown;
  lastSeenAt?: unknown;
}

type Opened = { token: string; account: { id: string; name: string; admin: boolean } };

function stamp(date = new Date()): string {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function summary(identity: Identity): AccountSummary {
  return { id: identity.id, name: identity.name, admin: identity.admin === true, createdAt: identity.createdAt };
}

function normalizeName(value: unknown): string {
  if (typeof value !== "string") throw new StoreError(400, "bad-request", { reason: "name" });
  const name = value.trim().toLowerCase();
  if (!NAME_RE.test(name)) throw new StoreError(400, "bad-request", { reason: "name" });
  return name;
}

function passwordOf(value: unknown): string {
  if (typeof value !== "string" || value.length < MIN_PASSWORD || value.length > 200) {
    throw new StoreError(400, "bad-request", { reason: "password" });
  }
  return value;
}

function tokenHash(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

function tokenUrlSafe(bytes: number): string {
  return randomBytes(bytes).toString("base64url");
}

function sameSecret(got: string, expected: string): boolean {
  if (!got || !expected) return false;
  const left = createHash("sha256").update(got).digest();
  const right = createHash("sha256").update(expected).digest();
  return timingSafeEqual(left, right);
}

/** Eight groups of an IPv6 address, without compression. An IPv4 tail counts as two groups. */
function ipv6Groups(address: string): string[] {
  const parts = (text: string): string[] => {
    if (!text) return [];
    const groups = text.split(":");
    const last = groups.at(-1) ?? "";
    if (!last.includes(".")) return groups;
    const [a = 0, b = 0, c = 0, d = 0] = last.split(".").map(Number);
    return [...groups.slice(0, -1), ((a << 8) | b).toString(16), ((c << 8) | d).toString(16)];
  };
  const [head = "", tail] = address.split("::");
  const left = parts(head);
  const right = tail === undefined ? [] : parts(tail);
  const middle = tail === undefined ? [] : Array<string>(8 - left.length - right.length).fill("0");
  return [...left, ...middle, ...right].map((group) => Number.parseInt(group, 16).toString(16));
}

/**
 * The key failed attempts count under: the address for IPv4, the /64 network for IPv6,
 * because one connection usually gets a whole /64. See ADR 0038.
 */
export function clientKey(address: string): string {
  const bare = address.split("%")[0] ?? address;
  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(bare);
  if (mapped?.[1]) return mapped[1];
  if (!isIPv6(bare)) return bare;
  return `${ipv6Groups(bare).slice(0, 4).join(":")}::/64`;
}

function slowDown(): StoreError {
  return new StoreError(429, "slow-down");
}

/**
 * Counts failures per key. `limit` failures within the window block the key until the
 * window after the last failure has passed. Memory only: a restart forgets it.
 */
export class Throttle {
  private readonly limit: number;
  private readonly windowMs: number;
  private readonly entries = new Map<string, { count: number; resetAt: number }>();

  constructor(limit: number, windowMs: number) {
    this.limit = limit;
    this.windowMs = windowMs;
  }

  blocked(key: string): boolean {
    const entry = this.entries.get(key);
    return entry !== undefined && entry.count >= this.limit && Date.now() < entry.resetAt;
  }

  fail(key: string): void {
    const now = Date.now();
    const entry = this.entries.get(key);
    if (!entry || now >= entry.resetAt) {
      this.entries.delete(key);
      this.entries.set(key, { count: 1, resetAt: now + this.windowMs });
      this.prune(now);
      return;
    }
    entry.count += 1;
    entry.resetAt = now + this.windowMs;
  }

  clear(key: string): void {
    this.entries.delete(key);
  }

  get size(): number {
    return this.entries.size;
  }

  /** Random names must not grow the map without bound. */
  private prune(now: number): void {
    if (this.entries.size <= THROTTLE_KEYS) return;
    for (const [key, entry] of this.entries) {
      if (entry.resetAt <= now) this.entries.delete(key);
    }
    for (const key of this.entries.keys()) {
      if (this.entries.size <= THROTTLE_KEYS) break;
      this.entries.delete(key);
    }
  }
}

export class Accounts {
  readonly root: string;
  private readonly identities: string;
  private readonly spaces: string;
  private readonly sessions: string;
  private readonly rounds: number;
  private readonly stores = new Map<string, Store>();
  /** Wrong passwords per account name. */
  private readonly names = new Throttle(NAME_LOCK_AFTER, LOCK_MS);
  /** Every failed unauthenticated attempt per client key (`clientKey`): logins and the setup token. */
  private readonly clients = new Throttle(CLIENT_LOCK_AFTER, LOCK_MS);
  private hashing = 0;
  private readonly hashingBy = new Map<string, number>();
  private dummy: Promise<string> | null = null;
  /** Opens the first account. Null once any account exists. Memory only, see ADR 0021. */
  private setupSecret: string | null;

  constructor(root: string, rounds = DEFAULT_ROUNDS, setupToken = tokenUrlSafe(24)) {
    this.root = root;
    this.rounds = rounds;
    this.identities = join(root, "identities");
    this.spaces = join(root, "spaces");
    this.sessions = join(root, "sessions");
    for (const path of [this.identities, this.spaces, this.sessions]) {
      mkdirSync(path, { recursive: true, mode: DIR_MODE });
    }
    // Opening every store repairs its change log now, not on the first request.
    for (const name of readdirSync(this.spaces)) {
      if (UUID_RE.test(name)) this.storeFor(name);
    }
    this.ensureAdmin();
    this.setupSecret = this.any() ? null : setupToken;
    this.sweep();
  }

  /** The setup token while the server waits for its first account, else null. */
  get setupToken(): string | null {
    return this.setupSecret;
  }

  registration(): "setup" | "closed" {
    return this.setupSecret === null ? "closed" : "setup";
  }

  /** Creates the admin with the setup token. The token is spent with it. */
  async setup(body: unknown, client: string): Promise<Opened> {
    const key = clientKey(client);
    if (this.clients.blocked(key)) throw slowDown();
    // Once there is an admin, the answer is setup-done whatever the body says. See API.md.
    if (this.setupSecret === null) throw new StoreError(403, "setup-done");
    if (!isRecord(body)) throw new StoreError(400, "bad-request");
    const name = normalizeName(body.name);
    const password = passwordOf(body.password);
    if (!sameSecret(typeof body.setupToken === "string" ? body.setupToken : "", this.setupSecret)) {
      this.clients.fail(key);
      throw new StoreError(401, "unauthorized");
    }
    const passwordHash = await this.hashPassword(password);
    // Two setup requests can race through the await. Only the first one becomes the admin.
    if (this.setupSecret === null) throw new StoreError(403, "setup-done");
    const identity = this.create(name, passwordHash, true);
    this.setupSecret = null;
    return this.openSession(identity);
  }

  /** The admin creates an account with a starting password. No session for it. */
  async createAccount(adminId: string, body: unknown): Promise<AccountSummary> {
    this.requireAdmin(adminId);
    if (!isRecord(body)) throw new StoreError(400, "bad-request");
    const name = normalizeName(body.name);
    const password = passwordOf(body.password);
    if (existsSync(join(this.identities, `${name}.json`))) throw new StoreError(409, "name-taken");
    const passwordHash = await this.hashPassword(password);
    return summary(this.create(name, passwordHash, false));
  }

  listAccounts(adminId: string): AccountSummary[] {
    this.requireAdmin(adminId);
    return this.allIdentities()
      .map(summary)
      .sort((left, right) => left.name.localeCompare(right.name));
  }

  /**
   * The admin changes an account: `name`, `password`, `admin`, whichever the body has. A new
   * password ends the account's sessions except the one asking. The last admin stays admin.
   * See ADR 0046.
   */
  async updateAccount(adminId: string, accountId: string, body: unknown, token: string): Promise<AccountSummary> {
    this.requireAdmin(adminId);
    if (!isRecord(body)) throw new StoreError(400, "bad-request");
    let identity = this.identityById(accountId);
    const name = body.name === undefined ? undefined : normalizeName(body.name);
    const password = body.password === undefined ? undefined : passwordOf(body.password);
    if (body.admin !== undefined && typeof body.admin !== "boolean") throw new StoreError(400, "bad-request", { reason: "admin" });
    const admin = body.admin as boolean | undefined;
    if (name === undefined && password === undefined && admin === undefined) throw new StoreError(400, "bad-request");
    if (name !== undefined && name !== identity.name && existsSync(join(this.identities, `${name}.json`))) {
      throw new StoreError(409, "name-taken");
    }
    if (admin === false && identity.admin === true && this.adminCount() <= 1) {
      throw new StoreError(400, "bad-request", { reason: "last admin" });
    }
    const passwordHash = password === undefined ? undefined : await this.hashPassword(password);
    // Read again: the hash took a while, and another change may have landed meanwhile.
    identity = this.identityById(accountId);
    const updated: Identity = { ...identity };
    if (passwordHash !== undefined) updated.passwordHash = passwordHash;
    if (admin === true) updated.admin = true;
    if (admin === false) delete updated.admin;
    if (name !== undefined && name !== identity.name) {
      if (existsSync(join(this.identities, `${name}.json`))) throw new StoreError(409, "name-taken");
      updated.name = name;
      atomicWrite(join(this.identities, `${name}.json`), Buffer.from(JSON.stringify(updated)));
      rmSync(join(this.identities, `${identity.name}.json`), { force: true });
    } else {
      atomicWrite(join(this.identities, `${identity.name}.json`), Buffer.from(JSON.stringify(updated)));
    }
    if (passwordHash !== undefined) this.endSessions(identity.id, token);
    return summary(updated);
  }

  /**
   * The admin deletes an account; the last admin stays. Its sessions end at once. Nothing is
   * erased: its notes and identity move to `deleted-accounts/<id>-<time>`. See ADR 0046.
   */
  deleteAccount(adminId: string, accountId: string): void {
    this.requireAdmin(adminId);
    const identity = this.identityById(accountId);
    if (identity.admin === true && this.adminCount() <= 1) throw new StoreError(400, "bad-request", { reason: "last admin" });
    // The identity goes first: from then on nobody signs in as it, and its sessions find no account.
    rmSync(join(this.identities, `${identity.name}.json`), { force: true });
    this.endSessions(identity.id);
    for (const key of [...this.stores.keys()]) {
      if (key === identity.id || key.startsWith(`${identity.id}/`)) this.stores.delete(key);
    }
    const deleted = join(this.root, "deleted-accounts");
    const target = join(deleted, `${identity.id}-${stamp().replace(/[:]/g, "-")}`);
    mkdirSync(deleted, { recursive: true, mode: DIR_MODE });
    const space = join(this.spaces, identity.id);
    if (existsSync(space)) renameSync(space, target);
    else mkdirSync(target, { mode: DIR_MODE });
    atomicWrite(join(target, "identity.json"), Buffer.from(JSON.stringify(identity)));
  }

  async login(body: unknown, client: string): Promise<Opened> {
    const key = clientKey(client);
    if (this.clients.blocked(key)) throw slowDown();
    if (!isRecord(body)) throw new StoreError(400, "bad-request");
    const name = normalizeName(body.name);
    const password = passwordOf(body.password);
    if (this.names.blocked(name)) throw slowDown();
    return this.limitHashing(key, async () => {
      const identity = this.readIdentity(name);
      const stored = identity ? identity.passwordHash : await this.dummyHash();
      if (!identity || !(await this.verifyPassword(password, stored))) {
        this.names.fail(name);
        this.clients.fail(key);
        throw new StoreError(401, "unauthorized");
      }
      this.names.clear(name);
      if (this.roundsOf(identity.passwordHash) < this.rounds) {
        const upgraded: Identity = { ...identity, passwordHash: await this.hashPassword(password) };
        atomicWrite(join(this.identities, `${name}.json`), Buffer.from(JSON.stringify(upgraded)));
      }
      return this.openSession(identity);
    });
  }

  /**
   * Failures are counted after the hash, so without a bound a burst of requests would all
   * reach PBKDF2 before the first one counts. Beyond the bound the answer is 429 at once.
   */
  private async limitHashing<T>(key: string, work: () => Promise<T>): Promise<T> {
    const mine = this.hashingBy.get(key) ?? 0;
    if (this.hashing >= MAX_HASHING || mine >= MAX_HASHING_PER_CLIENT) throw slowDown();
    this.hashing += 1;
    this.hashingBy.set(key, mine + 1);
    try {
      return await work();
    } finally {
      this.hashing -= 1;
      const left = (this.hashingBy.get(key) ?? 1) - 1;
      if (left > 0) this.hashingBy.set(key, left);
      else this.hashingBy.delete(key);
    }
  }

  logout(token: string): void {
    const path = join(this.sessions, `${tokenHash(token)}.json`);
    if (existsSync(path)) rmSync(path);
  }

  /** The account behind a session, or null. A session ends after `SESSION_IDLE_DAYS` without use. */
  accountId(token: string): string | null {
    if (!token) return null;
    const path = join(this.sessions, `${tokenHash(token)}.json`);
    const record = this.readSession(path);
    if (!record || typeof record.accountId !== "string") return null;
    const now = Date.now();
    const lastSeen = this.lastSeen(record);
    if (now - lastSeen > SESSION_IDLE_DAYS * DAY) {
      rmSync(path, { force: true });
      return null;
    }
    if (now - lastSeen > SESSION_TOUCH_MS) {
      atomicWrite(path, Buffer.from(JSON.stringify({ ...record, lastSeenAt: stamp() })));
    }
    return record.accountId;
  }

  storeFor(accountId: string): Store {
    const id = canonicalId(accountId);
    const cached = this.stores.get(id);
    if (cached) return cached;
    const space = join(this.spaces, id);
    if (!existsSync(space)) throw new StoreError(401, "unauthorized");
    const store = new Store(space);
    this.stores.set(id, store);
    return store;
  }

  /**
   * Workspaces of an account. `main` is the account's own space and always there; it is what
   * clients from before workspaces sync with. Others live under `workspaces/<id>`. See ADR 0020.
   * The list follows the account's order, see ADR 0043.
   */
  workspaces(accountId: string): WorkspaceList {
    const order = this.readOrder(accountId);
    const main = this.mainDeleted(accountId) ? [] : [this.mainWorkspace(accountId)];
    const list = [...main, ...this.readWorkspaces(accountId).map(toWorkspace)];
    if (!order) return { workspaces: list, ordered: false };
    const rank = new Map(order.map((id, index) => [id, index]));
    // Stable: workspaces missing from the stored order keep their default place after the ordered ones.
    const sorted = list
      .map((workspace, index) => ({ workspace, key: rank.get(workspace.id) ?? order.length + index }))
      .sort((a, b) => a.key - b.key)
      .map((entry) => entry.workspace);
    return { workspaces: sorted, ordered: true };
  }

  createWorkspace(accountId: string, body: unknown): Workspace {
    const name = workspaceName(isRecord(body) ? body.name : undefined);
    const list = this.readWorkspaces(accountId);
    // `main` counts too, while it exists: at most 50 workspaces in all.
    if (list.length + (this.mainDeleted(accountId) ? 0 : 1) >= MAX_WORKSPACES) throw new StoreError(400, "bad-request", { reason: "too many workspaces" });
    const entry = { id: randomUUID(), name };
    mkdirSync(join(this.spaceOf(accountId), "workspaces", entry.id), { recursive: true, mode: DIR_MODE });
    this.writeWorkspaces(accountId, [...list, entry]);
    return toWorkspace(entry);
  }

  /**
   * Changes name, symbol or icon, whichever the body has. The icon must already lie in the
   * workspace's blobs; `null` removes it. Any change stamps `updatedAt`. See ADR 0043.
   */
  updateWorkspace(accountId: string, workspaceId: string, body: unknown): Workspace {
    if (!isRecord(body)) throw new StoreError(400, "bad-request", { reason: "body" });
    const change: Look = {};
    let removesIcon = false;
    if (body.name !== undefined) change.name = workspaceName(body.name);
    if (body.symbol !== undefined) {
      const symbol = body.symbol;
      if (typeof symbol !== "string" || symbol.length > MAX_SYMBOL || !SYMBOL_RE.test(symbol)) {
        throw new StoreError(400, "bad-request", { reason: "symbol" });
      }
      change.symbol = symbol;
    }
    if (body.icon === null) {
      removesIcon = true;
    } else if (body.icon !== undefined) {
      if (typeof body.icon !== "string" || !SHA_RE.test(body.icon)) {
        throw new StoreError(400, "bad-request", { reason: "icon" });
      }
      change.icon = body.icon;
    }
    if (change.name === undefined && change.symbol === undefined && change.icon === undefined && !removesIcon) {
      throw new StoreError(400, "bad-request", { reason: "body" });
    }
    // Also answers 404 for an unknown workspace, before the icon check.
    const store = this.workspaceStore(accountId, workspaceId);
    if (change.icon !== undefined && !store.hasBlob(change.icon)) {
      throw new StoreError(400, "bad-request", { reason: "icon" });
    }
    const apply = (look: Look): Look => {
      const next: Look = { ...look, ...change, updatedAt: nowStamp() };
      if (removesIcon) delete next.icon;
      return next;
    };

    if (workspaceId === MAIN_WORKSPACE) {
      const look = apply(this.readMainLook(accountId));
      if (change.name !== undefined) atomicWrite(join(this.spaceOf(accountId), "name.txt"), Buffer.from(change.name));
      const { name: _name, ...rest } = look;
      atomicWrite(join(this.spaceOf(accountId), "main.json"), Buffer.from(JSON.stringify(rest, null, 2)));
      return this.mainWorkspace(accountId);
    }
    const id = canonicalId(workspaceId);
    const list = this.readWorkspaces(accountId);
    const index = list.findIndex((workspace) => workspace.id === id);
    if (index < 0) throw new StoreError(404, "not-found");
    const updated = { ...apply(list[index] ?? { id }), id } as StoredWorkspace;
    list[index] = updated;
    this.writeWorkspaces(accountId, list);
    return toWorkspace(updated);
  }

  /**
   * Reorders the workspaces in `ids` among the places they hold now. Workspaces not named keep
   * their place, so a device that knows only some of them moves only those. See ADR 0043.
   */
  orderWorkspaces(accountId: string, body: unknown): WorkspaceList {
    const raw = isRecord(body) ? body.ids : undefined;
    if (!Array.isArray(raw) || raw.length > MAX_WORKSPACES) throw new StoreError(400, "bad-request", { reason: "order" });
    const current = this.workspaces(accountId).workspaces.map((workspace) => workspace.id);
    const ids = raw.map((value) => {
      if (typeof value !== "string") throw new StoreError(400, "bad-request", { reason: "order" });
      return value === MAIN_WORKSPACE ? value : value.toLowerCase();
    });
    if (new Set(ids).size !== ids.length || ids.some((id) => !current.includes(id))) {
      throw new StoreError(400, "bad-request", { reason: "order" });
    }
    const named = new Set(ids);
    let next = 0;
    const order = current.map((id) => (named.has(id) ? (ids[next++] ?? id) : id));
    atomicWrite(join(this.spaceOf(accountId), "order.json"), Buffer.from(JSON.stringify(order, null, 2)));
    return this.workspaces(accountId);
  }

  /**
   * Deletes a workspace of the account; one always stays. Nothing is erased: the workspace's
   * files move to `deleted/<id>-<time>` in the account, so an admin can bring them back by hand.
   * `main` keeps its files in the account folder itself; a deleted `main` is marked in
   * `main.json`, and its routes, prefixed or not, answer 404 from then on. See ADR 0045.
   */
  deleteWorkspace(accountId: string, workspaceId: string): void {
    const isMain = workspaceId === MAIN_WORKSPACE;
    const id = isMain ? MAIN_WORKSPACE : canonicalId(workspaceId);
    const remaining = this.workspaces(accountId).workspaces;
    if (!remaining.some((workspace) => workspace.id === id)) throw new StoreError(404, "not-found");
    if (remaining.length <= 1) throw new StoreError(400, "bad-request", { reason: "last workspace" });
    const space = this.spaceOf(accountId);
    const deleted = join(space, "deleted");
    const target = join(deleted, `${id}-${nowStamp().replace(/[:]/g, "-")}`);
    mkdirSync(deleted, { recursive: true, mode: DIR_MODE });
    // Marked gone first: from then on no request reaches the files anymore.
    if (isMain) {
      const look = this.readMainLook(accountId);
      atomicWrite(join(space, "main.json"), Buffer.from(JSON.stringify({ ...look, deletedAt: nowStamp() }, null, 2)));
      this.stores.delete(canonicalId(accountId));
      mkdirSync(target, { recursive: true, mode: DIR_MODE });
      for (const name of ["notes", "blobs", "changes.jsonl"]) {
        const path = join(space, name);
        if (existsSync(path)) renameSync(path, join(target, name));
      }
    } else {
      this.writeWorkspaces(accountId, this.readWorkspaces(accountId).filter((workspace) => workspace.id !== id));
      this.stores.delete(`${canonicalId(accountId)}/${id}`);
      const folder = join(space, "workspaces", id);
      if (existsSync(folder)) renameSync(folder, target);
    }
    const order = this.readOrder(accountId);
    if (order) {
      atomicWrite(join(space, "order.json"), Buffer.from(JSON.stringify(order.filter((entry) => entry !== id), null, 2)));
    }
  }

  /** The store of one workspace. Unknown workspaces are 404, never created on the fly. */
  workspaceStore(accountId: string, workspaceId: string): Store {
    if (workspaceId === MAIN_WORKSPACE) {
      if (this.mainDeleted(accountId)) throw new StoreError(404, "not-found", { reason: "unknown workspace" });
      return this.storeFor(accountId);
    }
    const id = canonicalId(workspaceId);
    if (!this.readWorkspaces(accountId).some((workspace) => workspace.id === id)) {
      throw new StoreError(404, "not-found", { reason: "unknown workspace" });
    }
    const key = `${canonicalId(accountId)}/${id}`;
    const cached = this.stores.get(key);
    if (cached) return cached;
    const store = new Store(join(this.spaceOf(accountId), "workspaces", id));
    this.stores.set(key, store);
    return store;
  }

  private spaceOf(accountId: string): string {
    const space = join(this.spaces, canonicalId(accountId));
    if (!existsSync(space)) throw new StoreError(401, "unauthorized");
    return space;
  }

  private mainName(accountId: string): string {
    const path = join(this.spaceOf(accountId), "name.txt");
    if (!existsSync(path)) return DEFAULT_MAIN_NAME;
    const name = readFileSync(path, "utf8").trim();
    return name || DEFAULT_MAIN_NAME;
  }

  private readMainLook(accountId: string): Look {
    const path = join(this.spaceOf(accountId), "main.json");
    if (!existsSync(path)) return {};
    const parsed = JSON.parse(readFileSync(path, "utf8")) as unknown;
    return isRecord(parsed) ? lookOf(parsed) : {};
  }

  /** A deleted `main` is marked in `main.json`; its files lie under `deleted/`. */
  private mainDeleted(accountId: string): boolean {
    const path = join(this.spaceOf(accountId), "main.json");
    if (!existsSync(path)) return false;
    const parsed = JSON.parse(readFileSync(path, "utf8")) as unknown;
    return isRecord(parsed) && typeof parsed.deletedAt === "string";
  }

  private mainWorkspace(accountId: string): Workspace {
    return toWorkspace({ ...this.readMainLook(accountId), id: MAIN_WORKSPACE, name: this.mainName(accountId) });
  }

  private readWorkspaces(accountId: string): StoredWorkspace[] {
    const path = join(this.spaceOf(accountId), "workspaces.json");
    if (!existsSync(path)) return [];
    const parsed = JSON.parse(readFileSync(path, "utf8")) as unknown;
    if (!Array.isArray(parsed)) throw new Error(`${path}: not a list`);
    return parsed
      .filter((item) => isRecord(item) && typeof item.id === "string" && typeof item.name === "string")
      .map((item) => ({ ...lookOf(item as Record<string, unknown>), id: String(item.id), name: String(item.name) }));
  }

  private writeWorkspaces(accountId: string, list: StoredWorkspace[]): void {
    atomicWrite(join(this.spaceOf(accountId), "workspaces.json"), Buffer.from(JSON.stringify(list, null, 2)));
  }

  /** The stored order of workspace ids, or null while the account has none. */
  private readOrder(accountId: string): string[] | null {
    const path = join(this.spaceOf(accountId), "order.json");
    if (!existsSync(path)) return null;
    const parsed = JSON.parse(readFileSync(path, "utf8")) as unknown;
    if (!Array.isArray(parsed)) throw new Error(`${path}: not a list`);
    return parsed.filter((item): item is string => typeof item === "string");
  }

  /** Removes sessions past their idle limit. */
  sweep(): void {
    const now = Date.now();
    for (const name of readdirSync(this.sessions)) {
      if (!name.endsWith(".json")) continue;
      const path = join(this.sessions, name);
      const record = this.readSession(path);
      if (!record) continue;
      if (now - this.lastSeen(record) > SESSION_IDLE_DAYS * DAY) rmSync(path, { force: true });
    }
  }

  /** The first account is the admin. It also claims notes from before accounts existed. */
  private create(name: string, passwordHash: string, admin: boolean): Identity {
    // Re-checked here because callers hash the password in between.
    if (existsSync(join(this.identities, `${name}.json`))) throw new StoreError(409, "name-taken");
    const accountId = randomUUID();
    const space = join(this.spaces, accountId);
    mkdirSync(space, { mode: DIR_MODE });
    if (admin) this.claimLegacy(space);
    const identity: Identity = {
      id: accountId,
      name,
      passwordHash,
      createdAt: stamp(),
      ...(admin ? { admin: true } : {}),
    };
    atomicWrite(join(this.identities, `${name}.json`), Buffer.from(JSON.stringify(identity)));
    this.storeFor(accountId);
    return identity;
  }

  /** Servers from before ADR 0021 have accounts but no admin. The oldest one becomes it. */
  private ensureAdmin(): void {
    const all = this.allIdentities();
    if (all.length === 0 || all.some((identity) => identity.admin === true)) return;
    const oldest = all.reduce((left, right) =>
      right.createdAt < left.createdAt || (right.createdAt === left.createdAt && right.name < left.name) ? right : left,
    );
    atomicWrite(join(this.identities, `${oldest.name}.json`), Buffer.from(JSON.stringify({ ...oldest, admin: true })));
  }

  private identityById(accountId: string): Identity {
    const id = typeof accountId === "string" ? accountId.toLowerCase() : "";
    const identity = this.allIdentities().find((candidate) => candidate.id === id);
    if (!identity) throw new StoreError(404, "not-found");
    return identity;
  }

  private adminCount(): number {
    return this.allIdentities().filter((identity) => identity.admin === true).length;
  }

  /** Ends every session of an account, except the one with `keep` as its token. */
  private endSessions(accountId: string, keep?: string): void {
    const kept = keep ? `${tokenHash(keep)}.json` : null;
    for (const name of readdirSync(this.sessions)) {
      if (!name.endsWith(".json") || name === kept) continue;
      const path = join(this.sessions, name);
      if (this.readSession(path)?.accountId === accountId) rmSync(path, { force: true });
    }
  }

  private requireAdmin(accountId: string): void {
    if (this.allIdentities().some((identity) => identity.id === accountId && identity.admin === true)) return;
    throw new StoreError(403, "forbidden");
  }

  private allIdentities(): Identity[] {
    return readdirSync(this.identities)
      .filter((name) => name.endsWith(".json"))
      .map((name) => JSON.parse(readFileSync(join(this.identities, name), "utf8")) as Identity);
  }

  private claimLegacy(space: string): void {
    for (const name of ["notes", "blobs", "changes.jsonl", "state.json"]) {
      const source = join(this.root, name);
      const target = join(space, name);
      if (existsSync(source) && !existsSync(target)) renameSync(source, target);
    }
  }

  private openSession(identity: Identity): Opened {
    const token = tokenUrlSafe(32);
    const now = stamp();
    const record = { accountId: identity.id, createdAt: now, lastSeenAt: now };
    atomicWrite(join(this.sessions, `${tokenHash(token)}.json`), Buffer.from(JSON.stringify(record)));
    return { token, account: { id: identity.id, name: identity.name, admin: identity.admin === true } };
  }

  private readSession(path: string): SessionRecord | null {
    if (!existsSync(path)) return null;
    try {
      const record = JSON.parse(readFileSync(path, "utf8")) as unknown;
      if (isRecord(record)) return record;
    } catch {
      // A broken session file is no session.
    }
    rmSync(path, { force: true });
    return null;
  }

  /** Sessions from before idle expiry have no `lastSeenAt` and count from their creation. */
  private lastSeen(record: SessionRecord): number {
    const raw = typeof record.lastSeenAt === "string" ? record.lastSeenAt : record.createdAt;
    const parsed = typeof raw === "string" ? Date.parse(raw) : Number.NaN;
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private any(): boolean {
    return readdirSync(this.identities).some((name) => name.endsWith(".json"));
  }

  private readIdentity(name: string): Identity | null {
    const path = join(this.identities, `${name}.json`);
    if (!existsSync(path)) return null;
    return JSON.parse(readFileSync(path, "utf8")) as Identity;
  }

  /** Unknown names cost the same work as known ones, so timing does not reveal them. */
  private dummyHash(): Promise<string> {
    this.dummy ??= this.hashPassword("inkhash-dummy-password");
    return this.dummy;
  }

  private async hashPassword(password: string): Promise<string> {
    const salt = randomBytes(16);
    const digest = await pbkdf2Async(password, salt, this.rounds, 32, "sha256");
    return `pbkdf2_sha256$${this.rounds}$${salt.toString("hex")}$${digest.toString("hex")}`;
  }

  private roundsOf(stored: string): number {
    const rounds = Number(stored.split("$")[1]);
    return Number.isInteger(rounds) ? rounds : 0;
  }

  private async verifyPassword(password: string, stored: string): Promise<boolean> {
    const [scheme, roundsRaw, saltHex, digestHex] = stored.split("$");
    if (scheme !== "pbkdf2_sha256" || !roundsRaw || !saltHex || !digestHex) return false;
    const rounds = Number(roundsRaw);
    if (!Number.isInteger(rounds) || rounds < 1) return false;
    try {
      const digest = await pbkdf2Async(password, Buffer.from(saltHex, "hex"), rounds, 32, "sha256");
      const expected = Buffer.from(digestHex, "hex");
      if (digest.length !== expected.length) return false;
      return timingSafeEqual(digest, expected);
    } catch {
      return false;
    }
  }
}
