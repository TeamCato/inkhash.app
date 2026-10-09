/** The form of an account's vault. The server keeps it and cannot open it. See ADR 0052. */

import { StoreError, canonicalId } from "./store.js";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** What the server keeps of an account's vault: the key, wrapped with a passphrase it never sees. See ADR 0052. */
export interface Vault {
  keyId: string;
  kdf: { name: string; rounds: number; salt: string };
  wrapped: string;
  createdAt: string;
  updatedAt: string;
}

const KDF_NAMES = ["pbkdf2-sha256"];
const MIN_KDF_ROUNDS = 100_000;
const MAX_KDF_ROUNDS = 10_000_000;
const BASE64_RE = /^[A-Za-z0-9+/]+={0,2}$/;

function base64Field(value: unknown, reason: string, max: number): string {
  if (typeof value !== "string" || value.length < 4 || value.length > max || value.length % 4 !== 0 || !BASE64_RE.test(value)) {
    throw new StoreError(400, "bad-request", { reason });
  }
  return value;
}

/** Checks the form of a vault a device sends. The server cannot check more. */
export function vaultBody(body: unknown): Pick<Vault, "keyId" | "kdf" | "wrapped"> {
  if (!isRecord(body) || !isRecord(body.kdf)) throw new StoreError(400, "bad-request", { reason: "vault" });
  let keyId: string;
  try {
    keyId = canonicalId(body.keyId);
  } catch {
    throw new StoreError(400, "bad-request", { reason: "keyId" });
  }
  const { name, rounds, salt } = body.kdf;
  if (typeof name !== "string" || !KDF_NAMES.includes(name)) throw new StoreError(400, "bad-request", { reason: "kdf" });
  if (typeof rounds !== "number" || !Number.isInteger(rounds) || rounds < MIN_KDF_ROUNDS || rounds > MAX_KDF_ROUNDS) {
    throw new StoreError(400, "bad-request", { reason: "kdf" });
  }
  return {
    keyId,
    kdf: { name, rounds, salt: base64Field(salt, "kdf", 64) },
    wrapped: base64Field(body.wrapped, "wrapped", 256),
  };
}
