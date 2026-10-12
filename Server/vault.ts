/** The form of an account's vault. The server keeps it and cannot open it. See ADR 0052. */

import { StoreError, canonicalId } from "./store.js";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** What the server keeps of an account's vault: the key, wrapped with a recovery key it never sees. See ADR 0052, 0054. */
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

/** How long a pairing waits to be taken. See ADR 0054. */
export const PAIRING_TTL_MS = 5 * 60 * 1000;

interface OpenPairing {
  id: string;
  sealed: string;
  expiresAt: number;
}

/**
 * Hands the sealed account key from a device with an open vault to a new one. At most one per
 * account, in memory only, taken once. The server cannot open it: the secret is in the QR code.
 * See ADR 0054.
 */
export class Pairings {
  private readonly open = new Map<string, OpenPairing>();

  constructor(private readonly now: () => number = Date.now) {}

  /** Replaces whatever pairing the account had open. */
  offer(accountId: string, id: unknown, body: unknown): { expiresAt: string } {
    const pairingId = pairingIdOf(id);
    if (!isRecord(body)) throw new StoreError(400, "bad-request", { reason: "sealed" });
    const sealed = base64Field(body.sealed, "sealed", 512);
    const expiresAt = this.now() + PAIRING_TTL_MS;
    this.open.set(accountId, { id: pairingId, sealed, expiresAt });
    return { expiresAt: new Date(expiresAt).toISOString().replace(/\.\d{3}Z$/, "Z") };
  }

  /** The sealed key, once. Unknown, taken, withdrawn and expired pairings are all 404. */
  take(accountId: string, id: unknown): { sealed: string } {
    const pairingId = pairingIdOf(id);
    const pairing = this.open.get(accountId);
    if (!pairing || pairing.id !== pairingId || pairing.expiresAt <= this.now()) {
      if (pairing && pairing.expiresAt <= this.now()) this.open.delete(accountId);
      throw new StoreError(404, "not-found", { reason: "pairing" });
    }
    this.open.delete(accountId);
    return { sealed: pairing.sealed };
  }

  /** Idempotent: withdrawing a pairing that is gone is fine. */
  withdraw(accountId: string, id: unknown): void {
    const pairingId = pairingIdOf(id);
    if (this.open.get(accountId)?.id === pairingId) this.open.delete(accountId);
  }

  /** A reset or a deleted account makes an open pairing worthless. */
  drop(accountId: string): void {
    this.open.delete(accountId);
  }
}

function pairingIdOf(id: unknown): string {
  try {
    return canonicalId(id);
  } catch {
    throw new StoreError(400, "bad-request", { reason: "pairing" });
  }
}
