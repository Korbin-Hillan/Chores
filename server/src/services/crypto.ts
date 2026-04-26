import { createCipheriv, createDecipheriv, randomBytes, scryptSync } from "node:crypto";
import { env } from "../config/env.js";

// AES-256-GCM. The key-encryption key is derived from KEY_ENCRYPTION_SECRET via scrypt.
// Rotating KEY_ENCRYPTION_SECRET invalidates every previously stored ciphertext — by design.

const ALGORITHM = "aes-256-gcm";
const IV_LENGTH = 12;
const KEY = scryptSync(env.KEY_ENCRYPTION_SECRET, "choresapp-kek-salt", 32);

export interface EncryptedPayload {
  ciphertext: string;
  iv: string;
  tag: string;
}

export function encrypt(plaintext: string): EncryptedPayload {
  const iv = randomBytes(IV_LENGTH);
  const cipher = createCipheriv(ALGORITHM, KEY, iv);
  const encrypted = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  return {
    ciphertext: encrypted.toString("base64"),
    iv: iv.toString("base64"),
    tag: cipher.getAuthTag().toString("base64"),
  };
}

export function decrypt(payload: EncryptedPayload): string {
  const decipher = createDecipheriv(ALGORITHM, KEY, Buffer.from(payload.iv, "base64"));
  decipher.setAuthTag(Buffer.from(payload.tag, "base64"));
  const decrypted = Buffer.concat([
    decipher.update(Buffer.from(payload.ciphertext, "base64")),
    decipher.final(),
  ]);
  return decrypted.toString("utf8");
}
