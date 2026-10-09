/**
 * Filesystem store for inkhash notes.
 * The server stores bytes and JSON. It does not read drawings or derive tags.
 *
 * Note files are the truth. The change log is an index over them: it is appended
 * after the note is written and repaired on startup, see ADR 0015.
 */

import { createHash } from "node:crypto";
import {
  closeSync,
  existsSync,
  fsyncSync,
  ftruncateSync,
  mkdirSync,
  openSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const SHA_RE = /^[0-9a-f]{64}$/;

const MAX_TAGS = 50;
const MAX_TAG_LEN = 40;
const MAX_PAGES = 100;
const MAX_MARKDOWN = 1_000_000;
const MAX_TRANSCRIPT = 100_000;
const MAX_FOLDER = 200;
const MAX_FOLDER_SEGMENT = 60;
const MAX_ELEMENTS = 500;
const MAX_ELEMENT_SIZE = 20_000;
const MIN_ELEMENT_POS = -20_000;
const MAX_ELEMENT_POS = 40_000;
const MAX_MASK_POINTS = 500;
const MAX_LINK = 2000;
const LINK_PREFIXES = ["https://", "http://", "mailto:", "inkhash://note/"];
const COLOR_RE = /^#[0-9a-fA-F]{6}$/;

export const DEFAULT_CHANGE_LIMIT = 500;
export const MAX_CHANGE_LIMIT = 1000;

export interface ChangeEntry {
  cursor: number;
  noteId: string;
  revision: number;
  deleted: boolean;
}

export interface ChangePage {
  cursor: number;
  changes: ChangeEntry[];
  hasMore: boolean;
}

export class StoreError extends Error {
  readonly status: number;
  readonly code: string;
  readonly extra: Record<string, unknown>;

  constructor(status: number, code: string, extra: Record<string, unknown> = {}) {
    super(code);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

export class Conflict extends StoreError {
  readonly note: StoredNote;

  constructor(note: StoredNote) {
    super(409, "conflict", { note });
    this.note = note;
  }
}

export interface Page {
  id: string;
  blob: string;
  width: number;
  height: number;
  transcript: string;
  tags: string[];
  elements: Element[];
}

/** An image, shape, tape, link area or text excerpt on an ink page, see ADR 0028 and 0035. Absent keys are left out, never null. */
export interface Element {
  id: string;
  kind: "image" | "shape" | "tape" | "link" | "excerpt";
  x: number;
  y: number;
  width: number;
  height: number;
  rotation: number;
  z: number;
  blob?: string;
  frame?: { style: "none" | "solid" | "polaroid"; color: string; width: number; shadow: boolean };
  mask?: { kind: "circle" | "rectangle" | "freehand"; points: { x: number; y: number }[] };
  shape?: "line" | "rect" | "ellipse" | "triangle";
  stroke?: string;
  strokeWidth?: number;
  fill?: string;
  fillOpacity?: number;
  color?: string;
  link?: string;
}

/** Colour and pattern under the writing, for the whole note. See ADR 0042 and 0047. */
export interface Paper {
  color: string;
  pattern: "blank" | "grid" | "lines" | "dots";
  /** Distance between lines or dots in page points. Absent means the pattern's default. */
  spacing?: number;
}

const SPACING_MIN = 20;
const SPACING_MAX = 64;

export interface Note {
  schemaVersion: 1;
  id: string;
  kind: "text" | "ink";
  title: string;
  markdown: string | null;
  transcript: string | null;
  tags: string[];
  pages: Page[] | null;
  /** Folder path, segments joined by "/". Empty means no folder. */
  folder: string;
  favorite: boolean;
  /** Absent means the standard paper. */
  paper?: Paper;
  revision: number;
  /** Set by the client, absent on notes from before ADR 0048. */
  createdAt?: string;
  updatedAt: string;
  deletedAt: string | null;
}

/**
 * A note the server cannot read: everything a person wrote lies encrypted in `sealed`.
 * Revision, timestamps and the tombstone stay plain for syncing. See ADR 0052.
 */
export interface SealedNote {
  schemaVersion: 2;
  id: string;
  revision: number;
  updatedAt: string;
  deletedAt: string | null;
  /** Base64 of the device's ciphertext. The server only checks its form and length. */
  sealed: string;
}

export type StoredNote = Note | SealedNote;

export function isSealed(note: StoredNote): note is SealedNote {
  return note.schemaVersion === 2;
}

/** Longest `sealed`, in characters. The JSON body limit stops longer ones anyway. */
export const MAX_SEALED = 2_000_000;
const BASE64_RE = /^[A-Za-z0-9+/]*={0,2}$/;

/** Written once a sealed workspace has dropped its plain blobs. See ADR 0052. */
const PURGED_MARKER = "plain-purged";

export function canonicalId(value: unknown): string {
  if (typeof value !== "string" || !UUID_RE.test(value.toLowerCase())) {
    throw new StoreError(400, "bad-request", { reason: "invalid id" });
  }
  return value.toLowerCase();
}

export function validTag(tag: unknown): tag is string {
  if (typeof tag !== "string" || tag.length < 1 || tag.length > MAX_TAG_LEN) return false;
  if (tag !== tag.trim()) return false;
  for (const ch of tag) {
    const code = ch.codePointAt(0) ?? 0;
    if (code < 32 || ch === "#" || /\s/u.test(ch)) return false;
  }
  return true;
}

export function nowStamp(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

/** Directories and files only the server user can read. See ADR 0038. */
export const DIR_MODE = 0o700;
export const FILE_MODE = 0o600;

export function atomicWrite(path: string, data: Buffer): void {
  mkdirSync(dirname(path), { recursive: true, mode: DIR_MODE });
  const tmp = `${path}.tmp`;
  // `open` sets the mode only on create; a leftover from a crash would keep its old one.
  rmSync(tmp, { force: true });
  const fd = openSync(tmp, "w", FILE_MODE);
  try {
    writeFileSync(fd, data);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  renameSync(tmp, path);
  syncDirectory(dirname(path));
}

/** Makes a rename durable. Without it a crash can undo the rename on some filesystems. */
function syncDirectory(path: string): void {
  const fd = openSync(path, "r");
  try {
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
}

const STAMP_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;

/** A UTC timestamp in the form of `updatedAt`, and a real moment: no 31 February. */
export function validStamp(value: unknown): value is string {
  if (typeof value !== "string" || !STAMP_RE.test(value)) return false;
  const time = Date.parse(value);
  return Number.isFinite(time) && new Date(time).toISOString().replace(/\.\d{3}Z$/, "Z") === value;
}

/** A folder path the client wrote. The server checks the form only, like tags. */
export function validFolder(folder: unknown): folder is string {
  if (typeof folder !== "string" || folder.length > MAX_FOLDER) return false;
  if (folder === "") return true;
  return folder.split("/").every((segment) => {
    if (segment.length < 1 || segment.length > MAX_FOLDER_SEGMENT || segment !== segment.trim()) return false;
    for (const ch of segment) {
      if ((ch.codePointAt(0) ?? 0) < 32) return false;
    }
    return true;
  });
}

function contentKey(note: Note): string {
  return JSON.stringify([
    note.kind,
    note.title,
    note.markdown,
    note.transcript,
    note.tags,
    note.pages,
    note.folder ?? "",
    note.favorite ?? false,
    note.paper ?? null,
    note.createdAt ?? null,
  ]);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function badElement(): StoreError {
  return new StoreError(400, "bad-request", { reason: "element" });
}

function finite(value: unknown, min = -Infinity, max = Infinity): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < min || value > max) throw badElement();
  return value;
}

function color(value: unknown): string {
  if (typeof value !== "string" || !COLOR_RE.test(value)) throw badElement();
  return value.toUpperCase();
}

function oneOf<T extends string>(value: unknown, allowed: readonly T[]): T {
  if (typeof value !== "string" || !allowed.includes(value as T)) throw badElement();
  return value as T;
}

/** Optional keys: null and absent mean the same and are both left out, so equal content serializes equally. */
function present(record: Record<string, unknown>, key: string): boolean {
  return key in record && record[key] != null;
}

function frame(value: unknown): NonNullable<Element["frame"]> {
  if (!isRecord(value)) throw badElement();
  if (typeof value.shadow !== "boolean") throw badElement();
  return {
    style: oneOf(value.style, ["none", "solid", "polaroid"] as const),
    color: color(value.color),
    width: finite(value.width, 0, 100),
    shadow: value.shadow,
  };
}

function mask(value: unknown): NonNullable<Element["mask"]> {
  if (!isRecord(value)) throw badElement();
  const kind = oneOf(value.kind, ["circle", "rectangle", "freehand"] as const);
  const raw = value.points ?? [];
  if (!Array.isArray(raw) || raw.length > MAX_MASK_POINTS) throw badElement();
  if (kind === "freehand" ? raw.length < 3 : raw.length !== 0) throw badElement();
  const points = raw.map((point: unknown) => {
    if (!isRecord(point)) throw badElement();
    return { x: finite(point.x, 0, 1), y: finite(point.y, 0, 1) };
  });
  return { kind, points };
}

function link(value: unknown): string {
  if (typeof value !== "string" || value.length > MAX_LINK) throw badElement();
  if (!LINK_PREFIXES.some((prefix) => value.startsWith(prefix))) throw badElement();
  return value;
}

/** A text note has a colour only; its pattern is always blank. Blank paper has no spacing. */
function paperOf(value: unknown, kind: Note["kind"]): Paper {
  const bad = () => new StoreError(400, "bad-request", { reason: "paper" });
  if (!isRecord(value) || typeof value.color !== "string" || !COLOR_RE.test(value.color)) throw bad();
  const pattern = value.pattern ?? "blank";
  if (pattern !== "blank" && pattern !== "grid" && pattern !== "lines" && pattern !== "dots") throw bad();
  if (kind === "text" && pattern !== "blank") throw bad();
  const spacing = value.spacing ?? undefined;
  if (spacing !== undefined) {
    if (!Number.isInteger(spacing) || (spacing as number) < SPACING_MIN || (spacing as number) > SPACING_MAX) throw bad();
    if (pattern === "blank") throw bad();
  }
  return { color: value.color.toUpperCase(), pattern, ...(spacing !== undefined ? { spacing: spacing as number } : {}) };
}

const UUID_PART = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
/** `inkhash://note/<id>/page/<id>?rect=…` or `inkhash://note/<id>?text…`, see ADR 0037. */
const EXCERPT_RE = new RegExp(`^inkhash://note/${UUID_PART}(/page/${UUID_PART}\\?rect=[0-9.,]+|\\?text(&[a-z]+=[A-Za-z0-9%._~-]*)*)$`);

/** Checks one element and rebuilds it with a fixed key order, so the retry comparison is deterministic. */
export function normalizeElement(value: unknown): Element {
  if (!isRecord(value)) throw badElement();
  let id: string;
  try {
    id = canonicalId(value.id);
  } catch {
    throw badElement();
  }
  const kind = oneOf(value.kind, ["image", "shape", "tape", "link", "excerpt"] as const);
  const z = value.z;
  if (typeof z !== "number" || !Number.isInteger(z)) throw badElement();
  const element: Element = {
    id,
    kind,
    x: finite(value.x, MIN_ELEMENT_POS, MAX_ELEMENT_POS),
    y: finite(value.y, MIN_ELEMENT_POS, MAX_ELEMENT_POS),
    width: finite(value.width, 0, MAX_ELEMENT_SIZE),
    height: finite(value.height, 0, MAX_ELEMENT_SIZE),
    rotation: finite(value.rotation),
    z,
  };
  if (element.width === 0 || element.height === 0) throw badElement();

  const image = kind === "image";
  if (image) {
    if (typeof value.blob !== "string" || !SHA_RE.test(value.blob)) throw badElement();
    element.blob = value.blob;
  } else if (present(value, "blob")) {
    throw badElement();
  }
  for (const key of ["frame", "mask"]) {
    if (!image && present(value, key)) throw badElement();
  }
  if (present(value, "frame")) element.frame = frame(value.frame);
  if (present(value, "mask")) element.mask = mask(value.mask);

  const shape = kind === "shape";
  if (shape) {
    element.shape = oneOf(value.shape, ["line", "rect", "ellipse", "triangle"] as const);
  }
  for (const key of ["shape", "stroke", "strokeWidth", "fill", "fillOpacity"]) {
    if (!shape && present(value, key)) throw badElement();
  }
  if (present(value, "stroke")) element.stroke = color(value.stroke);
  if (present(value, "strokeWidth")) element.strokeWidth = finite(value.strokeWidth, 0, 100);
  if (present(value, "fill")) element.fill = color(value.fill);
  if (present(value, "fillOpacity")) element.fillOpacity = finite(value.fillOpacity, 0, 1);

  if (present(value, "color")) {
    if (kind !== "tape") throw badElement();
    element.color = color(value.color);
  }

  if (present(value, "link")) {
    element.link = link(value.link);
  } else if (kind === "link" || kind === "excerpt") {
    throw badElement();
  }
  // An excerpt shows another note: a page rectangle or text. The server does not look into that note.
  if (kind === "excerpt" && !EXCERPT_RE.test(element.link ?? "")) throw badElement();
  return element;
}

function elements(value: unknown): Element[] {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > MAX_ELEMENTS) throw badElement();
  return value.map(normalizeElement);
}

export class Store {
  readonly root: string;
  readonly notes: string;
  readonly blobs: string;
  /**
   * The account has a vault: notes must come sealed, blobs encrypted. Set by `Accounts`
   * on every request. See ADR 0052.
   */
  sealed = false;
  private readonly changesPath: string;
  /** Notes stored as plain JSON. Once the account is sealed, they go up again encrypted. */
  private readonly plain = new Set<string>();
  /** Latest log entry per note. Older entries of the same note carry no information for a client. */
  private readonly latest = new Map<string, ChangeEntry>();
  private head = 0;

  constructor(root: string) {
    this.root = root;
    this.notes = join(root, "notes");
    this.blobs = join(root, "blobs");
    mkdirSync(this.notes, { recursive: true, mode: DIR_MODE });
    mkdirSync(this.blobs, { recursive: true, mode: DIR_MODE });
    this.changesPath = join(root, "changes.jsonl");
    this.load();
  }

  get cursor(): number {
    return this.head;
  }

  /**
   * One entry per note, ordered by cursor. A cursor ahead of the log, e.g. after a restore
   * from an older backup, is treated as 0 so the device checks every note again.
   */
  changes(after: number, limit = DEFAULT_CHANGE_LIMIT): ChangePage {
    if (!Number.isInteger(limit) || limit < 1 || limit > MAX_CHANGE_LIMIT) {
      throw new StoreError(400, "bad-request", { reason: "limit" });
    }
    const from = after > this.head ? 0 : after;
    const pending = [...this.latest.values()].filter((entry) => entry.cursor > from).sort((a, b) => a.cursor - b.cursor);
    const page = pending.slice(0, limit);
    const hasMore = pending.length > limit;
    const cursor = hasMore ? (page.at(-1)?.cursor ?? this.head) : this.head;
    return { cursor, changes: page.map((entry) => ({ ...entry })), hasMore };
  }

  getNote(noteId: string): StoredNote {
    const id = canonicalId(noteId);
    const note = this.readNote(id);
    if (!note) throw new StoreError(404, "not-found");
    return note;
  }

  putNote(noteId: string, baseRevision: number, body: unknown): [number, StoredNote] {
    const id = canonicalId(noteId);
    if (isRecord(body) && body.schemaVersion === 2) return this.putSealed(id, baseRevision, body);
    if (this.sealed) throw new StoreError(400, "bad-request", { reason: "sealed" });
    const note = this.normalize(id, body);
    const existing = this.readNote(id);
    // A client from before ADR 0048 leaves the date out; the note keeps the one it has.
    if (note.createdAt === undefined && existing && !isSealed(existing) && existing.createdAt !== undefined) note.createdAt = existing.createdAt;
    if (!existing) {
      if (baseRevision !== 0) throw new StoreError(404, "not-found", { reason: "unknown note" });
      return [201, this.writeNew(note, 1, null)];
    }
    if (existing.revision !== baseRevision) {
      // A retry whose first attempt was stored but whose answer got lost.
      if (!isSealed(existing) && existing.deletedAt === null && contentKey(existing) === contentKey(note)) return [200, existing];
      throw new Conflict(existing);
    }
    return [200, this.writeNew(note, existing.revision + 1, null)];
  }

  /**
   * A sealed note. `deleted: true` stores it as a tombstone, so notes in the trash can be
   * resealed without coming back for a moment. A retry is the same `sealed` with the same
   * tombstone state. See ADR 0052.
   */
  private putSealed(id: string, baseRevision: number, body: Record<string, unknown>): [number, SealedNote] {
    if (!this.sealed) throw new StoreError(400, "bad-request", { reason: "no vault" });
    if (canonicalId(String(body.id ?? "")) !== id) throw new StoreError(400, "bad-request", { reason: "id mismatch" });
    const sealed = body.sealed;
    if (typeof sealed !== "string" || sealed.length === 0 || sealed.length > MAX_SEALED || sealed.length % 4 !== 0 || !BASE64_RE.test(sealed)) {
      throw new StoreError(400, "bad-request", { reason: "sealed" });
    }
    const deleted = body.deleted ?? false;
    if (typeof deleted !== "boolean") throw new StoreError(400, "bad-request", { reason: "deleted" });
    const existing = this.readNote(id);
    if (!existing) {
      if (baseRevision !== 0) throw new StoreError(404, "not-found", { reason: "unknown note" });
      return [201, this.writeSealed(id, sealed, 1, deleted ? nowStamp() : null)];
    }
    if (existing.revision !== baseRevision) {
      if (isSealed(existing) && existing.sealed === sealed && (existing.deletedAt !== null) === deleted) return [200, existing];
      throw new Conflict(existing);
    }
    const deletedAt = deleted ? (existing.deletedAt ?? nowStamp()) : null;
    return [200, this.writeSealed(id, sealed, existing.revision + 1, deletedAt)];
  }

  private writeSealed(id: string, sealed: string, revision: number, deletedAt: string | null): SealedNote {
    const now = nowStamp();
    const stored: SealedNote = { schemaVersion: 2, id, revision, updatedAt: deletedAt ?? now, deletedAt, sealed };
    if (deletedAt === null) stored.updatedAt = now;
    this.commit(stored);
    return stored;
  }

  deleteNote(noteId: string, baseRevision: number): StoredNote {
    const id = canonicalId(noteId);
    const existing = this.readNote(id);
    if (!existing) throw new StoreError(404, "not-found");
    if (existing.revision !== baseRevision) throw new Conflict(existing);
    if (existing.deletedAt !== null) return existing;
    existing.deletedAt = nowStamp();
    existing.revision += 1;
    existing.updatedAt = existing.deletedAt;
    this.commit(existing);
    return existing;
  }

  /**
   * Plain accounts name a blob by its SHA-256. Sealed ones by a name only the devices can make;
   * a blob named by its own hash is plain and refused there. See ADR 0052.
   */
  putBlob(digest: string, data: Buffer): void {
    if (!SHA_RE.test(digest)) throw new StoreError(400, "bad-request", { reason: "invalid blob" });
    const actual = createHash("sha256").update(data).digest("hex");
    if (this.sealed) {
      if (actual === digest) throw new StoreError(400, "bad-request", { reason: "sealed" });
    } else if (actual !== digest) {
      throw new StoreError(400, "bad-request", { reason: "hash mismatch" });
    }
    const path = join(this.blobs, digest);
    if (existsSync(path)) return;
    atomicWrite(path, data);
  }

  hasBlob(digest: string): boolean {
    return SHA_RE.test(digest) && existsSync(join(this.blobs, digest));
  }

  getBlob(digest: string): Buffer {
    if (!SHA_RE.test(digest)) throw new StoreError(400, "bad-request", { reason: "invalid blob" });
    const path = join(this.blobs, digest);
    if (!existsSync(path)) throw new StoreError(404, "not-found");
    return readFileSync(path);
  }

  /** How many notes still lie here as plain JSON. */
  get plainCount(): number {
    return this.plain.size;
  }

  /** True once `purgePlain` has run here. */
  get purged(): boolean {
    return existsSync(join(this.root, PURGED_MARKER));
  }

  /**
   * Deletes every plain blob, recognised by a name that is its own SHA-256, except those in
   * `keep`. Only once all notes are sealed, and only once per store. See ADR 0052.
   */
  purgePlain(keep: ReadonlySet<string>): number {
    if (!this.sealed || this.plain.size > 0 || this.purged) return 0;
    let removed = 0;
    for (const name of readdirSync(this.blobs)) {
      if (!SHA_RE.test(name) || keep.has(name)) continue;
      const path = join(this.blobs, name);
      if (createHash("sha256").update(readFileSync(path)).digest("hex") === name) {
        rmSync(path, { force: true });
        removed += 1;
      }
    }
    atomicWrite(join(this.root, PURGED_MARKER), Buffer.from(`${nowStamp()}\n`));
    return removed;
  }

  /** Removes a blob if it is plain. For a workspace picture that was replaced. */
  dropPlainBlob(digest: string): void {
    if (!SHA_RE.test(digest)) return;
    const path = join(this.blobs, digest);
    if (existsSync(path) && createHash("sha256").update(readFileSync(path)).digest("hex") === digest) rmSync(path, { force: true });
  }

  /**
   * Moves notes and blobs to `target` and starts empty. The change log stays, so cursors keep
   * growing and no device skips a change. For resetting a vault, see ADR 0052.
   */
  wipe(target: string): void {
    mkdirSync(target, { recursive: true, mode: DIR_MODE });
    for (const [path, name] of [[this.notes, "notes"], [this.blobs, "blobs"]] as const) {
      if (existsSync(path)) renameSync(path, join(target, name));
      mkdirSync(path, { recursive: true, mode: DIR_MODE });
    }
    rmSync(join(this.root, PURGED_MARKER), { force: true });
    this.latest.clear();
    this.plain.clear();
  }

  private normalize(noteId: string, body: unknown): Note {
    if (!isRecord(body)) throw new StoreError(400, "bad-request", { reason: "note must be an object" });
    if (body.schemaVersion !== 1) throw new StoreError(400, "bad-request", { reason: "unsupported schema" });
    if (canonicalId(String(body.id ?? "")) !== noteId) {
      throw new StoreError(400, "bad-request", { reason: "id mismatch" });
    }
    const kind = body.kind;
    if (kind !== "text" && kind !== "ink") throw new StoreError(400, "bad-request", { reason: "kind" });
    const title = body.title;
    if (typeof title !== "string" || title.length > 200) {
      throw new StoreError(400, "bad-request", { reason: "title" });
    }
    const tags = body.tags;
    if (!Array.isArray(tags) || tags.length > MAX_TAGS || !tags.every(validTag)) {
      throw new StoreError(400, "bad-request", { reason: "tags" });
    }
    const markdown = "markdown" in body ? body.markdown : null;
    const transcript = "transcript" in body ? body.transcript : null;
    const pages = "pages" in body ? body.pages : null;
    // Clients from before folders leave both out.
    const folder = "folder" in body && body.folder != null ? body.folder : "";
    if (!validFolder(folder)) throw new StoreError(400, "bad-request", { reason: "folder" });
    const favorite = "favorite" in body && body.favorite != null ? body.favorite : false;
    if (typeof favorite !== "boolean") throw new StoreError(400, "bad-request", { reason: "favorite" });
    const paper = "paper" in body && body.paper != null ? paperOf(body.paper, kind) : undefined;
    const createdAt = "createdAt" in body && body.createdAt != null ? body.createdAt : undefined;
    if (createdAt !== undefined && !validStamp(createdAt)) {
      throw new StoreError(400, "bad-request", { reason: "createdAt" });
    }
    if ("deletedAt" in body && body.deletedAt != null) {
      throw new StoreError(400, "bad-request", { reason: "use DELETE" });
    }
    if (kind === "text") {
      if (typeof markdown !== "string" || markdown.length > MAX_MARKDOWN) {
        throw new StoreError(400, "bad-request", { reason: "markdown" });
      }
      if (transcript != null || pages != null) {
        throw new StoreError(400, "bad-request", { reason: "text notes have no ink payload" });
      }
      return {
        schemaVersion: 1,
        id: noteId,
        kind,
        title,
        markdown,
        transcript: null,
        tags,
        pages: null,
        folder,
        favorite,
        ...(paper ? { paper } : {}),
        ...(createdAt ? { createdAt } : {}),
        revision: 0,
        updatedAt: "",
        deletedAt: null,
      };
    }
    if (markdown != null) throw new StoreError(400, "bad-request", { reason: "ink notes have no markdown" });
    if (typeof transcript !== "string" || transcript.length > MAX_TRANSCRIPT) {
      throw new StoreError(400, "bad-request", { reason: "transcript" });
    }
    return {
      schemaVersion: 1,
      id: noteId,
      kind,
      title,
      markdown: null,
      transcript,
      tags,
      pages: this.pages(pages),
      folder,
      favorite,
      ...(paper ? { paper } : {}),
      ...(createdAt ? { createdAt } : {}),
      revision: 0,
      updatedAt: "",
      deletedAt: null,
    };
  }

  private pages(pages: unknown): Page[] {
    if (!Array.isArray(pages) || pages.length > MAX_PAGES) {
      throw new StoreError(400, "bad-request", { reason: "pages" });
    }
    return pages.map((page) => {
      if (!isRecord(page)) throw new StoreError(400, "bad-request", { reason: "page" });
      const blob = page.blob;
      if (typeof blob !== "string" || !SHA_RE.test(blob)) {
        throw new StoreError(400, "bad-request", { reason: "blob" });
      }
      const width = page.width;
      const height = page.height;
      if (typeof width !== "number" || typeof height !== "number" || !Number.isFinite(width) || !Number.isFinite(height)) {
        throw new StoreError(400, "bad-request", { reason: "page size" });
      }
      if (width < 1 || width > 10000 || height < 1 || height > 10000) {
        throw new StoreError(400, "bad-request", { reason: "page size" });
      }
      const transcript = "transcript" in page ? page.transcript : "";
      const tags = "tags" in page ? page.tags : [];
      if (typeof transcript !== "string" || transcript.length > MAX_TRANSCRIPT) {
        throw new StoreError(400, "bad-request", { reason: "page transcript" });
      }
      if (!Array.isArray(tags) || tags.length > MAX_TAGS || !tags.every(validTag)) {
        throw new StoreError(400, "bad-request", { reason: "page tags" });
      }
      return {
        id: canonicalId(String(page.id ?? "")),
        blob,
        width,
        height,
        transcript,
        tags,
        elements: elements(page.elements),
      };
    });
  }

  private writeNew(note: Note, revision: number, deletedAt: string | null): Note {
    const stored: Note = { ...note, revision, updatedAt: nowStamp(), deletedAt };
    this.commit(stored);
    return stored;
  }

  /** The note file first, then the log. A crash in between is repaired by `load`. */
  private commit(note: StoredNote): void {
    atomicWrite(this.notePath(note.id), Buffer.from(JSON.stringify(note, null, 2)));
    this.track(note);
    this.append(note);
  }

  private track(note: StoredNote): void {
    if (isSealed(note)) this.plain.delete(note.id);
    else this.plain.add(note.id);
  }

  private append(note: StoredNote): void {
    const entry: ChangeEntry = {
      cursor: this.head + 1,
      noteId: note.id,
      revision: note.revision,
      deleted: note.deletedAt !== null,
    };
    const fd = openSync(this.changesPath, "a", FILE_MODE);
    try {
      writeFileSync(fd, `${JSON.stringify(entry)}\n`);
      fsyncSync(fd);
    } finally {
      closeSync(fd);
    }
    this.head = entry.cursor;
    this.latest.set(entry.noteId, entry);
  }

  private load(): void {
    for (const entry of this.readLog()) {
      this.head = Math.max(this.head, entry.cursor);
      this.latest.set(entry.noteId, entry);
    }
    // Servers before ADR 0015 kept the cursor in state.json, and it could run ahead of the log.
    // It is only read, so cursors handed out back then never get reused.
    const statePath = join(this.root, "state.json");
    if (existsSync(statePath)) {
      const state = JSON.parse(readFileSync(statePath, "utf8")) as { cursor?: unknown };
      if (typeof state.cursor === "number" && Number.isInteger(state.cursor)) {
        this.head = Math.max(this.head, state.cursor);
      }
    }

    for (const name of readdirSync(this.blobs)) {
      if (name.endsWith(".tmp")) rmSync(join(this.blobs, name), { force: true });
    }
    const onDisk = new Set<string>();
    for (const name of readdirSync(this.notes).sort()) {
      if (name.endsWith(".tmp")) {
        rmSync(join(this.notes, name), { force: true });
        continue;
      }
      if (!name.endsWith(".json")) continue;
      const id = name.slice(0, -".json".length);
      if (!UUID_RE.test(id)) continue;
      let note: StoredNote | null;
      try {
        note = this.readNote(id);
      } catch {
        throw new Error(`${join(this.notes, name)}: unreadable note`);
      }
      if (!note) continue;
      onDisk.add(id);
      this.track(note);
      const logged = this.latest.get(id);
      const deleted = note.deletedAt !== null;
      if (!logged || logged.revision !== note.revision || logged.deleted !== deleted) this.append(note);
    }
    // An entry whose file is gone would make every device fail on fetch, forever.
    for (const id of [...this.latest.keys()]) {
      if (!onDisk.has(id)) this.latest.delete(id);
    }
  }

  /** Reads the log. A torn last line from a crash during append is cut off; anything else broken is fatal. */
  private readLog(): ChangeEntry[] {
    if (!existsSync(this.changesPath)) return [];
    const raw = readFileSync(this.changesPath);
    let text = raw.toString("utf8");
    const end = text.lastIndexOf("\n") + 1;
    if (end < text.length) {
      const fd = openSync(this.changesPath, "r+");
      try {
        ftruncateSync(fd, Buffer.byteLength(text.slice(0, end), "utf8"));
        fsyncSync(fd);
      } finally {
        closeSync(fd);
      }
      text = text.slice(0, end);
    }
    const entries: ChangeEntry[] = [];
    for (const [index, line] of text.split("\n").entries()) {
      if (!line.trim()) continue;
      let entry: Partial<ChangeEntry>;
      try {
        entry = JSON.parse(line) as Partial<ChangeEntry>;
      } catch {
        throw new Error(`${this.changesPath}:${index + 1}: broken change entry`);
      }
      if (
        typeof entry.cursor !== "number" ||
        typeof entry.noteId !== "string" ||
        typeof entry.revision !== "number" ||
        typeof entry.deleted !== "boolean"
      ) {
        throw new Error(`${this.changesPath}:${index + 1}: broken change entry`);
      }
      entries.push(entry as ChangeEntry);
    }
    return entries;
  }

  private readNote(noteId: string): StoredNote | null {
    const path = this.notePath(noteId);
    if (!existsSync(path)) return null;
    const stored = JSON.parse(readFileSync(path, "utf8")) as StoredNote;
    if (isSealed(stored)) return stored;
    const note = stored;
    // Notes stored before folders existed.
    note.folder ??= "";
    note.favorite ??= false;
    // Pages stored before elements, ADR 0028.
    for (const page of note.pages ?? []) page.elements ??= [];
    return note;
  }

  private notePath(noteId: string): string {
    if (!UUID_RE.test(noteId)) throw new StoreError(400, "bad-request", { reason: "invalid id" });
    return join(this.notes, `${noteId}.json`);
  }
}
