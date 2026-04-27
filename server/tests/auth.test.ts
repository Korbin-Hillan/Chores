import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { startMongo, stopMongo, clearMongo } from "./helpers/mongo.js";

process.env.MONGO_URI ??= "mongodb://placeholder/test";
process.env.JWT_SECRET ??= "test_jwt_secret_at_least_thirty_two_characters_long_xx";
process.env.KEY_ENCRYPTION_SECRET ??= "test_key_encryption_secret_at_least_thirty_two_xx";

let app: FastifyInstance;

beforeAll(async () => {
  await startMongo();
  const { buildApp } = await import("../src/app.js");
  app = await buildApp({ skipMongo: true });
});

afterEach(async () => clearMongo());
afterAll(async () => {
  await app.close();
  await stopMongo();
});

describe("POST /auth/signup", () => {
  it("creates a user and returns tokens", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/signup",
      payload: { email: "test@example.com", password: "password123", displayName: "Test User" },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json<{ accessToken: string; refreshToken: string; user: { email: string } }>();
    expect(body.accessToken).toBeTruthy();
    expect(body.refreshToken).toBeTruthy();
    expect(body.user.email).toBe("test@example.com");
  });

  it("rejects duplicate email", async () => {
    const payload = { email: "dupe@example.com", password: "password123", displayName: "Dupe" };
    await app.inject({ method: "POST", url: "/auth/signup", payload });
    const res = await app.inject({ method: "POST", url: "/auth/signup", payload });
    expect(res.statusCode).toBe(400);
  });

  it("rejects short password", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/signup",
      payload: { email: "a@b.com", password: "short", displayName: "X" },
    });
    expect(res.statusCode).toBe(400);
  });
});

describe("POST /auth/login", () => {
  it("returns tokens for valid credentials", async () => {
    await app.inject({
      method: "POST",
      url: "/auth/signup",
      payload: { email: "login@example.com", password: "password123", displayName: "Login User" },
    });

    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "login@example.com", password: "password123" },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ accessToken: string }>();
    expect(body.accessToken).toBeTruthy();
  });

  it("rejects wrong password", async () => {
    await app.inject({
      method: "POST",
      url: "/auth/signup",
      payload: { email: "wrong@example.com", password: "password123", displayName: "Wrong" },
    });
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "wrong@example.com", password: "badpassword" },
    });
    expect(res.statusCode).toBe(401);
  });
});

describe("POST /auth/refresh", () => {
  it("rotates the refresh token", async () => {
    const signup = await app.inject({
      method: "POST",
      url: "/auth/signup",
      payload: { email: "refresh@example.com", password: "password123", displayName: "Refresh" },
    });
    const { refreshToken } = signup.json<{ refreshToken: string }>();

    const res = await app.inject({
      method: "POST",
      url: "/auth/refresh",
      payload: { refreshToken },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ accessToken: string; refreshToken: string }>();
    expect(body.refreshToken).not.toBe(refreshToken);
  });

  it("rejects a reused refresh token", async () => {
    const signup = await app.inject({
      method: "POST",
      url: "/auth/signup",
      payload: { email: "reuse@example.com", password: "password123", displayName: "Reuse" },
    });
    const { refreshToken } = signup.json<{ refreshToken: string }>();

    await app.inject({ method: "POST", url: "/auth/refresh", payload: { refreshToken } });
    const res = await app.inject({
      method: "POST",
      url: "/auth/refresh",
      payload: { refreshToken },
    });
    expect(res.statusCode).toBe(401);
  });
});

describe("User avatars", () => {
  it("stores, fetches, and removes the current user's avatar", async () => {
    const signup = await app.inject({
      method: "POST",
      url: "/auth/signup",
      payload: { email: "avatar@example.com", password: "password123", displayName: "Avatar User" },
    });
    const { accessToken, user } = signup.json<{ accessToken: string; user: { id: string } }>();
    const imageBase64 = Buffer.from("fake image bytes").toString("base64");

    const update = await app.inject({
      method: "PUT",
      url: "/auth/me/avatar",
      headers: { authorization: `Bearer ${accessToken}` },
      payload: { imageBase64, mimeType: "image/png" },
    });
    expect(update.statusCode).toBe(200);
    expect(update.json<{ hasAvatar: boolean }>().hasAvatar).toBe(true);

    const photo = await app.inject({
      method: "GET",
      url: `/auth/users/${user.id}/avatar`,
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(photo.statusCode).toBe(200);
    expect(photo.headers["content-type"]).toContain("image/png");
    expect(photo.body).toBe("fake image bytes");

    const remove = await app.inject({
      method: "DELETE",
      url: "/auth/me/avatar",
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(remove.statusCode).toBe(204);

    const missing = await app.inject({
      method: "GET",
      url: `/auth/users/${user.id}/avatar`,
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(missing.statusCode).toBe(404);
  });
});
