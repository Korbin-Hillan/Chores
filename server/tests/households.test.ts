import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { startMongo, stopMongo, clearMongo } from "./helpers/mongo.js";

process.env.MONGO_URI ??= "mongodb://placeholder/test";
process.env.JWT_SECRET ??= "test_jwt_secret_at_least_thirty_two_characters_long_xx";
process.env.KEY_ENCRYPTION_SECRET ??=
  "test_key_encryption_secret_at_least_thirty_two_chars_xx";

let app: FastifyInstance;

beforeAll(async () => {
  await startMongo();
  const { buildApp } = await import("../src/app.js");
  app = await buildApp({ skipMongo: true });
});

afterEach(async () => clearMongo());
afterAll(async () => {
  if (app) await app.close();
  await stopMongo();
});

describe("household admin routes", () => {
  it("accepts :id params in admin membership checks", async () => {
    const signup = await app.inject({
      method: "POST",
      url: "/auth/signup",
      payload: {
        email: "admin@example.com",
        password: "password123",
        displayName: "Admin User",
      },
    });
    expect(signup.statusCode).toBe(201);
    const { accessToken } = signup.json<{ accessToken: string }>();

    const create = await app.inject({
      method: "POST",
      url: "/households",
      headers: { authorization: `Bearer ${accessToken}` },
      payload: { name: "Test Household" },
    });
    expect(create.statusCode).toBe(201);
    const {
      household: { id: householdId },
    } = create.json<{ household: { id: string } }>();

    const regenerate = await app.inject({
      method: "POST",
      url: `/households/${householdId}/regenerate-invite`,
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(regenerate.statusCode).toBe(200);
    expect(regenerate.json<{ inviteCode: string }>().inviteCode).toBeTruthy();
  });
});
