import { randomInt } from "node:crypto";

// Excludes ambiguous characters: 0, O, I, 1
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export function generateInviteCode(length = 8): string {
  return Array.from({ length }, () => ALPHABET[randomInt(ALPHABET.length)]!).join("");
}
