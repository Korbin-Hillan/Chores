import { createHash, randomBytes } from "node:crypto";
import { RefreshToken } from "../models/refreshToken.js";

const REFRESH_TOKEN_TTL_DAYS = 30;

export function hashRefreshToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function generateRefreshToken(): string {
  return randomBytes(40).toString("hex");
}

export async function createRefreshToken(userId: string): Promise<string> {
  const token = generateRefreshToken();
  const expiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000);
  await RefreshToken.create({ tokenHash: hashRefreshToken(token), userId, expiresAt });
  return token;
}

export async function rotateRefreshToken(
  incomingToken: string,
): Promise<{ userId: string; newToken: string } | null> {
  const hash = hashRefreshToken(incomingToken);
  const existing = await RefreshToken.findOneAndDelete({ tokenHash: hash });
  if (!existing) return null;
  if (existing.expiresAt < new Date()) return null;

  const userId = existing.userId.toString();
  const newToken = await createRefreshToken(userId);
  return { userId, newToken };
}

export async function deleteAllRefreshTokens(userId: string): Promise<void> {
  await RefreshToken.deleteMany({ userId });
}
