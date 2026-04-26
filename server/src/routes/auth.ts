import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { User, toSafeUser } from "../models/user.js";
import { hashPassword, verifyPassword } from "../services/passwords.js";
import { createRefreshToken, rotateRefreshToken, deleteAllRefreshTokens } from "../services/tokens.js";
import { AppError } from "../utils/errors.js";
import { requireAuth } from "../middleware/requireAuth.js";

const signUpBody = z.object({
  email: z.string().email(),
  password: z.string().min(8, "Password must be at least 8 characters"),
  displayName: z.string().min(1).max(50).trim(),
});

const loginBody = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

const refreshBody = z.object({
  refreshToken: z.string().min(1),
});

export async function authRoutes(app: FastifyInstance): Promise<void> {
  app.post("/signup", async (request, reply) => {
    const body = signUpBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    const existing = await User.findOne({ email: body.data.email });
    if (existing) throw new AppError(400, "VALIDATION_FAILED", "Email already in use");

    const passwordHash = await hashPassword(body.data.password);
    const user = await User.create({
      email: body.data.email,
      passwordHash,
      displayName: body.data.displayName,
    });

    const accessToken = app.jwt.sign({ userId: user._id.toHexString() });
    const refreshToken = await createRefreshToken(user._id.toHexString());

    return reply.status(201).send({
      accessToken,
      refreshToken,
      user: toSafeUser(user),
    });
  });

  app.post("/login", async (request, reply) => {
    const body = loginBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    const user = await User.findOne({ email: body.data.email });
    const valid = user ? await verifyPassword(body.data.password, user.passwordHash) : false;

    // Always run the comparison to prevent timing attacks
    if (!user || !valid) {
      throw new AppError(401, "UNAUTHORIZED", "Invalid email or password");
    }

    const accessToken = app.jwt.sign({ userId: user._id.toHexString() });
    const refreshToken = await createRefreshToken(user._id.toHexString());

    return reply.send({ accessToken, refreshToken, user: toSafeUser(user) });
  });

  app.post("/refresh", async (request, reply) => {
    const body = refreshBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    const result = await rotateRefreshToken(body.data.refreshToken);
    if (!result) throw new AppError(401, "UNAUTHORIZED", "Invalid or expired refresh token");

    const user = await User.findById(result.userId);
    if (!user) throw new AppError(401, "UNAUTHORIZED", "User not found");

    const accessToken = app.jwt.sign({ userId: user._id.toHexString() });

    return reply.send({ accessToken, refreshToken: result.newToken, user: toSafeUser(user) });
  });

  app.post("/logout", { preHandler: [requireAuth] }, async (request, reply) => {
    await deleteAllRefreshTokens(request.user.userId);
    return reply.status(204).send();
  });
}
