import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { Conflict, Store, StoreError, type Note } from "../store.js";

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

test("create, update, conflict, and tombstone", () => {
  const root = mkdtempSync(join(tmpdir(), "inkhash-"));
  try {
    const store = new Store(root);
    const noteId = "6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10";
    const [status, created] = store.putNote(noteId, 0, textNote(noteId, "# Hallo\n", ["eigen"]));
    assert.equal(status, 201);
    assert.equal(created.revision, 1);
    assert.equal(created.markdown, "# Hallo\n");
    assert.deepEqual(created.tags, ["eigen"]);
    assert.notEqual(created.updatedAt, "2026-09-30T06:00:00Z");

    const updated = textNote(noteId, "zweiter text", ["eigen"]);
    const [, stored] = store.putNote(noteId, 1, updated);
    assert.equal(stored.revision, 2);
    assert.equal(stored.markdown, "zweiter text");

    assert.throws(
      () => store.putNote(noteId, 1, textNote(noteId, "anderes gerät", ["eigen"])),
      (error: unknown) => error instanceof Conflict && error.note.revision === 2,
    );

    const deleted = store.deleteNote(noteId, 2);
    assert.ok(deleted.deletedAt);
    assert.equal(deleted.markdown, "zweiter text");
    const changes = store.changes(0);
    assert.equal(changes.cursor, 3);
    assert.equal(changes.changes.length, 1, "one entry per note");
    assert.equal(changes.changes[0]?.deleted, true);
    assert.equal(changes.changes[0]?.revision, 3);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("rejects path escape and bad tags", () => {
  const root = mkdtempSync(join(tmpdir(), "inkhash-"));
  try {
    const store = new Store(root);
    const noteId = "6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10";
    assert.throws(() => store.getNote("../etc/passwd"), StoreError);
    assert.throws(() => store.putBlob("../x", Buffer.from("nope")), StoreError);
    assert.throws(() => store.putNote(noteId, 0, textNote(noteId, "# Hallo\n", ["#nope"])), StoreError);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("blob hash and fixture roundtrip", () => {
  const root = mkdtempSync(join(tmpdir(), "inkhash-"));
  try {
    const store = new Store(root);
    const digest = "a".repeat(64);
    const payload = Buffer.from("ink");
    assert.throws(() => store.putBlob(digest, payload), StoreError);
    const real = createHash("sha256").update(payload).digest("hex");
    store.putBlob(real, payload);
    assert.deepEqual(store.getBlob(real), payload);

    const fixturePath = join(dirname(fileURLToPath(import.meta.url)), "../../../docs/fixtures/note-ink.json");
    const fixture = JSON.parse(readFileSync(fixturePath, "utf8")) as Note;
    const [status, stored] = store.putNote(fixture.id, 0, fixture);
    assert.equal(status, 201);
    assert.equal(stored.transcript, "Reise #alpen");
    assert.deepEqual(stored.tags, ["alpen"]);
    assert.equal(stored.pages?.[0]?.blob, fixture.pages?.[0]?.blob);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

function withRoot(fn: (root: string) => void): void {
  const root = mkdtempSync(join(tmpdir(), "inkhash-"));
  try {
    fn(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

const A = "6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10";
const B = "8a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d";
const C = "0d9e8f7a-6b5c-4d3e-8f2a-1b0c9d8e7f6a";

function logLines(root: string): string[] {
  return readFileSync(join(root, "changes.jsonl"), "utf8").split("\n").filter(Boolean);
}

test("retry of a stored write answers with the stored note", () => {
  withRoot((root) => {
    const store = new Store(root);
    store.putNote(A, 0, textNote(A, "eins"));
    const [, second] = store.putNote(A, 1, textNote(A, "zwei"));
    const [status, retried] = store.putNote(A, 1, textNote(A, "zwei"));
    assert.equal(status, 200);
    assert.equal(retried.revision, second.revision);
    assert.equal(store.cursor, 2, "a retry is not a new change");
  });
});

test("retry does not bring back a deleted note", () => {
  withRoot((root) => {
    const store = new Store(root);
    store.putNote(A, 0, textNote(A, "eins"));
    store.deleteNote(A, 1);
    assert.throws(() => store.putNote(A, 1, textNote(A, "eins")), Conflict);
  });
});

test("unknown note with a base revision is not found", () => {
  withRoot((root) => {
    const store = new Store(root);
    assert.throws(
      () => store.putNote(A, 4, textNote(A)),
      (error: unknown) => error instanceof StoreError && !(error instanceof Conflict) && error.status === 404,
    );
  });
});

test("note written without its log entry is announced after restart", () => {
  withRoot((root) => {
    const first = new Store(root);
    first.putNote(A, 0, textNote(A, "eins"));
    // Simulate a crash between the note file and the log append.
    const stored = JSON.parse(readFileSync(join(root, "notes", `${A}.json`), "utf8")) as Note;
    writeFileSync(join(root, "notes", `${A}.json`), JSON.stringify({ ...stored, revision: 2, markdown: "zwei" }));
    writeFileSync(join(root, "notes", `${B}.json`), JSON.stringify({ ...textNote(B), revision: 1 }));
    writeFileSync(join(root, "notes", `${C}.json.tmp`), "{");

    const store = new Store(root);
    const page = store.changes(1);
    assert.deepEqual(
      page.changes.map((entry) => [entry.noteId, entry.revision]).sort(),
      [
        [A, 2],
        [B, 1],
      ].sort(),
    );
    assert.equal(page.cursor, 3);
    assert.equal(existsSync(join(root, "notes", `${C}.json.tmp`)), false);
    assert.equal(new Store(root).cursor, 3, "a clean restart appends nothing");
  });
});

test("torn last log line is cut off, a broken middle line is fatal", () => {
  withRoot((root) => {
    new Store(root).putNote(A, 0, textNote(A));
    appendFileSync(join(root, "changes.jsonl"), '{"cursor":2,"noteId":"');
    const store = new Store(root);
    assert.equal(store.cursor, 1);
    assert.equal(logLines(root).length, 1);

    writeFileSync(join(root, "changes.jsonl"), `garbage\n${logLines(root)[0]}\n`);
    assert.throws(() => new Store(root), /broken change entry/);
  });
});

test("legacy state.json keeps cursors from going backwards", () => {
  withRoot((root) => {
    writeFileSync(join(root, "state.json"), JSON.stringify({ cursor: 10 }));
    const store = new Store(root);
    store.putNote(A, 0, textNote(A));
    assert.equal(store.changes(0).changes[0]?.cursor, 11);
    assert.equal(new Store(root).cursor, 11);
  });
});

test("log entry without a note file is not served", () => {
  withRoot((root) => {
    new Store(root).putNote(A, 0, textNote(A));
    rmSync(join(root, "notes", `${A}.json`));
    assert.deepEqual(new Store(root).changes(0).changes, []);
  });
});

test("changes come in pages", () => {
  withRoot((root) => {
    const store = new Store(root);
    store.putNote(A, 0, textNote(A));
    store.putNote(B, 0, textNote(B));
    store.putNote(C, 0, textNote(C));
    store.putNote(A, 1, textNote(A, "neu"));

    const first = store.changes(0, 2);
    assert.deepEqual(first.changes.map((entry) => entry.noteId), [B, C]);
    assert.equal(first.hasMore, true);
    assert.equal(first.cursor, 3);
    const second = store.changes(first.cursor, 2);
    assert.deepEqual(second.changes.map((entry) => entry.noteId), [A]);
    assert.equal(second.hasMore, false);
    assert.equal(second.cursor, 4);

    assert.throws(() => store.changes(0, 0), StoreError);
    assert.throws(() => store.changes(0, 5000), StoreError);
  });
});

test("cursor ahead of the log starts over", () => {
  withRoot((root) => {
    const store = new Store(root);
    store.putNote(A, 0, textNote(A));
    const page = store.changes(99);
    assert.equal(page.changes.length, 1);
    assert.equal(page.cursor, 1);
  });
});

test("folder and favorite are checked and old notes read without them", () => {
  const root = mkdtempSync(join(tmpdir(), "inkhash-"));
  try {
    const store = new Store(root);
    const noteId = "6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10";
    for (const folder of ["/Reisen", "Reisen/", "Reisen//Dänemark", " Reisen", 4]) {
      assert.throws(() => store.putNote(noteId, 0, { ...textNote(noteId), folder }), StoreError);
    }
    assert.throws(() => store.putNote(noteId, 0, { ...textNote(noteId), favorite: "ja" }), StoreError);
    const legacy: Record<string, unknown> = { ...textNote(noteId) };
    delete legacy.folder;
    delete legacy.favorite;
    const [, created] = store.putNote(noteId, 0, legacy);
    assert.equal(created.folder, "");
    assert.equal(created.favorite, false);
    const [, moved] = store.putNote(noteId, 1, { ...textNote(noteId), folder: "Reisen/Dänemark", favorite: true });
    assert.equal(moved.revision, 2);
    assert.equal(store.getNote(noteId).folder, "Reisen/Dänemark");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

const PAGE = "11111111-2222-4333-8444-555555555555";
const DRAWING = "a".repeat(64);
const PHOTO = "b".repeat(64);

function inkNote(id: string, elements?: unknown[]): Record<string, unknown> {
  const page: Record<string, unknown> = { id: PAGE, blob: DRAWING, width: 768, height: 1024, transcript: "", tags: [] };
  if (elements) page.elements = elements;
  return {
    schemaVersion: 1,
    id,
    kind: "ink",
    title: "",
    revision: 0,
    updatedAt: "2026-09-30T06:00:00Z",
    deletedAt: null,
    markdown: null,
    transcript: "",
    tags: [],
    pages: [page],
    folder: "",
    favorite: false,
  };
}

function base(id: string, kind: string): Record<string, unknown> {
  return { id, kind, x: 100, y: 200, width: 300, height: 150, rotation: 0.5, z: 1 };
}

const E1 = "2222aaaa-1111-4222-8333-444455556666";
const E2 = "3333bbbb-1111-4222-8333-444455556666";
const E3 = "4444cccc-1111-4222-8333-444455556666";
const E4 = "5555dddd-1111-4222-8333-444455556666";
const E5 = "6666eeee-1111-4222-8333-444455556666";
const E6 = "7777ffff-1111-4222-8333-444455556666";

test("elements of every kind round trip in a fixed key order", () => {
  withRoot((root) => {
    const store = new Store(root);
    const sent = [
      {
        link: "https://example.com",
        mask: { kind: "freehand", points: [{ x: 0, y: 0 }, { x: 1, y: 0 }, { x: 0.5, y: 1 }] },
        frame: { style: "polaroid", color: "#ffffff", width: 12, shadow: true },
        blob: PHOTO,
        ...base(E1.toUpperCase(), "image"),
      },
      { ...base(E2, "shape"), shape: "ellipse", stroke: "#ff0000", strokeWidth: 2, fill: null, fillOpacity: 0.3 },
      { ...base(E3, "tape"), color: "#aabbcc" },
      { ...base(E4, "link"), z: -2, link: "inkhash://note/8a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d", blob: null },
      { ...base(E5, "excerpt"), link: "inkhash://note/8a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d?text&section=Ziele%20neu" },
      { ...base(E6, "excerpt"), link: "inkhash://note/8a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d/page/1a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d?rect=10,20.5,300,120" },
    ];
    const [status, stored] = store.putNote(B, 0, inkNote(B, sent));
    assert.equal(status, 201);
    const elements = store.getNote(B).pages?.[0]?.elements;
    assert.deepEqual(elements, stored.pages?.[0]?.elements);
    assert.deepEqual(elements, [
      {
        ...base(E1, "image"),
        blob: PHOTO,
        frame: { style: "polaroid", color: "#FFFFFF", width: 12, shadow: true },
        mask: { kind: "freehand", points: [{ x: 0, y: 0 }, { x: 1, y: 0 }, { x: 0.5, y: 1 }] },
        link: "https://example.com",
      },
      { ...base(E2, "shape"), shape: "ellipse", stroke: "#FF0000", strokeWidth: 2, fillOpacity: 0.3 },
      { ...base(E3, "tape"), color: "#AABBCC" },
      { ...base(E4, "link"), z: -2, link: "inkhash://note/8a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d" },
      { ...base(E5, "excerpt"), link: "inkhash://note/8a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d?text&section=Ziele%20neu" },
      { ...base(E6, "excerpt"), link: "inkhash://note/8a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d/page/1a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d?rect=10,20.5,300,120" },
    ]);
    assert.deepEqual(Object.keys(elements?.[0] ?? {}), [
      "id", "kind", "x", "y", "width", "height", "rotation", "z", "blob", "frame", "mask", "link",
    ]);
    const onDisk = JSON.parse(readFileSync(join(root, "notes", `${B}.json`), "utf8")) as Note;
    assert.deepEqual(onDisk.pages?.[0]?.elements, elements);
  });
});

test("bad elements are rejected", () => {
  withRoot((root) => {
    const store = new Store(root);
    const tooMany = Array.from({ length: 501 }, () => ({ ...base(E3, "tape") }));
    const bad: unknown[] = [
      { ...base(E1, "sticker") },
      { ...base(E3, "tape"), color: "red" },
      { ...base(E3, "tape"), color: "#12345" },
      { ...base(E1, "image") },
      { ...base(E1, "image"), blob: "B".repeat(64) },
      { ...base(E2, "shape"), shape: "rect", blob: PHOTO },
      { ...base(E2, "shape") },
      { ...base(E3, "tape"), shape: "rect" },
      { ...base(E4, "link") },
      { ...base(E4, "link"), link: "javascript:alert(1)" },
      { ...base(E4, "link"), link: `https://${"x".repeat(2000)}` },
      { ...base(E3, "tape"), width: 0 },
      { ...base(E3, "tape"), height: 20001 },
      { ...base(E3, "tape"), x: 40001 },
      { ...base(E3, "tape"), z: 1.5 },
      { ...base(E3, "tape"), rotation: "0" },
      { ...base("nope", "tape") },
      { ...base(E1, "image"), blob: PHOTO, mask: { kind: "freehand", points: [{ x: 0, y: 0 }, { x: 1, y: 1 }] } },
      { ...base(E1, "image"), blob: PHOTO, mask: { kind: "circle", points: [{ x: 0, y: 0 }, { x: 1, y: 1 }, { x: 1, y: 0 }] } },
      { ...base(E1, "image"), blob: PHOTO, mask: { kind: "freehand", points: [{ x: 0, y: 0 }, { x: 2, y: 1 }, { x: 1, y: 0 }] } },
      { ...base(E1, "image"), blob: PHOTO, frame: { style: "fancy", color: "#000000", width: 1, shadow: false } },
      { ...base(E3, "tape"), frame: { style: "none", color: "#000000", width: 1, shadow: false } },
      { ...base(E5, "excerpt") },
      { ...base(E5, "excerpt"), link: "https://example.com" },
      { ...base(E5, "excerpt"), link: "inkhash://note/8a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d" },
      { ...base(E5, "excerpt"), link: "inkhash://note/8a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d?text&section=a b" },
      { ...base(E5, "excerpt"), link: "inkhash://note/8a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d/page/x?rect=1,2,3,4" },
      { ...base(E5, "excerpt"), link: "inkhash://note/8a2b4c6d-1e3f-4a5b-9c7d-0e1f2a3b4c5d", section: "Ziele" },
    ];
    for (const element of bad) {
      assert.throws(
        () => store.putNote(B, 0, inkNote(B, [element])),
        (error: unknown) => error instanceof StoreError && error.status === 400 && error.extra.reason === "element",
        JSON.stringify(element).slice(0, 120),
      );
    }
    assert.throws(() => store.putNote(B, 0, inkNote(B, tooMany)), StoreError);
    assert.throws(() => store.putNote(B, 0, { ...inkNote(B), pages: [{ ...(inkNote(B).pages as object[])[0], elements: {} }] }), StoreError);
    assert.equal(store.cursor, 0);
  });
});

test("pages without elements are served with an empty list", () => {
  withRoot((root) => {
    const store = new Store(root);
    const [, created] = store.putNote(B, 0, inkNote(B));
    assert.deepEqual(created.pages?.[0]?.elements, []);

    // A note stored by a server before ADR 0028.
    const path = join(root, "notes", `${B}.json`);
    const legacy = JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown> & { pages: Record<string, unknown>[] };
    for (const page of legacy.pages) delete page.elements;
    writeFileSync(path, JSON.stringify(legacy));
    const reopened = new Store(root);
    assert.deepEqual(reopened.getNote(B).pages?.[0]?.elements, []);
    const [status, retried] = reopened.putNote(B, 0, inkNote(B, []));
    assert.equal(status, 200, "an empty list equals a missing one in the retry comparison");
    assert.equal(retried.revision, 1);
  });
});

test("elements take part in the retry comparison", () => {
  withRoot((root) => {
    const store = new Store(root);
    const tape = { ...base(E3, "tape"), color: "#aabbcc" };
    store.putNote(B, 0, inkNote(B, [tape]));
    const [status, retried] = store.putNote(B, 0, inkNote(B, [{ color: "#AABBCC", ...base(E3.toUpperCase(), "tape"), link: null }]));
    assert.equal(status, 200);
    assert.equal(retried.revision, 1);
    assert.throws(() => store.putNote(B, 0, inkNote(B, [{ ...tape, x: 101 }])), Conflict);
    assert.throws(() => store.putNote(B, 0, inkNote(B, [])), Conflict);
    assert.equal(store.cursor, 1);
  });
});

test("paper is checked, stored and part of the retry comparison", () => {
  const root = mkdtempSync(join(tmpdir(), "inkhash-"));
  try {
    const store = new Store(root);
    const noteId = "6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10";
    const reason = (body: Record<string, unknown>) => {
      try {
        store.putNote(noteId, 0, body);
      } catch (error) {
        return error instanceof StoreError ? error.extra.reason : "other";
      }
      return "stored";
    };
    assert.equal(reason({ ...textNote(noteId), paper: { color: "blau" } }), "paper");
    assert.equal(reason({ ...textNote(noteId), paper: "#FAF5E8" }), "paper");
    assert.equal(reason({ ...textNote(noteId), paper: { color: "#FAF5E8", pattern: "lines" } }), "paper");
    assert.equal(reason({ ...textNote(noteId), paper: { color: "#FAF5E8", pattern: "hexagons" } }), "paper");

    // Standard paper: no key at all, also when the client sends null.
    const [, plain] = store.putNote(noteId, 0, { ...textNote(noteId), paper: null });
    assert.equal("paper" in plain, false);

    const [, cream] = store.putNote(noteId, 1, { ...textNote(noteId), paper: { color: "#faf5e8" } });
    assert.deepEqual(cream.paper, { color: "#FAF5E8", pattern: "blank" });
    assert.deepEqual(store.getNote(noteId).paper, { color: "#FAF5E8", pattern: "blank" });

    // A retry with the same paper is the stored note; another paper is a conflict.
    const [status, again] = store.putNote(noteId, 1, { ...textNote(noteId), paper: { color: "#FAF5E8", pattern: "blank" } });
    assert.equal(status, 200);
    assert.equal(again.revision, 2);
    assert.throws(() => store.putNote(noteId, 1, { ...textNote(noteId), paper: { color: "#EAF1FA" } }), Conflict);

    const inkId = "11111111-2222-4333-8444-555555555555";
    const [, lined] = store.putNote(inkId, 0, { ...inkNote(inkId), paper: { color: "#FDFDFC", pattern: "lines" } });
    assert.deepEqual(lined.paper, { color: "#FDFDFC", pattern: "lines" });

    // Spacing (ADR 0047): a whole number in range, only with a pattern, and part of the content.
    const otherInk = "22222222-2222-4333-8444-555555555555";
    const inkReason = (paper: unknown) => {
      try {
        store.putNote(otherInk, 0, { ...inkNote(otherInk), paper });
      } catch (error) {
        return error instanceof StoreError ? error.extra.reason : "other";
      }
      return "stored";
    };
    assert.equal(inkReason({ color: "#FDFDFC", pattern: "grid", spacing: 19 }), "paper");
    assert.equal(inkReason({ color: "#FDFDFC", pattern: "grid", spacing: 65 }), "paper");
    assert.equal(inkReason({ color: "#FDFDFC", pattern: "grid", spacing: 30.5 }), "paper");
    assert.equal(inkReason({ color: "#FDFDFC", pattern: "grid", spacing: "40" }), "paper");
    assert.equal(inkReason({ color: "#FDFDFC", pattern: "blank", spacing: 40 }), "paper");
    assert.equal(reason({ ...textNote(noteId), paper: { color: "#FAF5E8", spacing: 40 } }), "paper");

    const [, wide] = store.putNote(inkId, 1, { ...inkNote(inkId), paper: { color: "#FDFDFC", pattern: "lines", spacing: 48 } });
    assert.deepEqual(wide.paper, { color: "#FDFDFC", pattern: "lines", spacing: 48 });
    assert.deepEqual(store.getNote(inkId).paper, { color: "#FDFDFC", pattern: "lines", spacing: 48 });
    assert.throws(
      () => store.putNote(inkId, 1, { ...inkNote(inkId), paper: { color: "#FDFDFC", pattern: "lines", spacing: 40 } }),
      Conflict,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
