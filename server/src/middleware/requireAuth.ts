import type { FastifyReply, FastifyRequest } from "fastify";
import { AppError } from "../utils/errors.js";

export async function requireAuth(request: FastifyRequest, reply: FastifyReply): Promise<void> {
  try {
    await request.jwtVerify();
  } catch {
    throw new AppError(401, "UNAUTHORIZED", "Invalid or expired token");
  }
  // request.user is now typed as { userId: string } via types/fastify.d.ts
  void reply;
}
