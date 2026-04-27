import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { startMongo, stopMongo, clearMongo } from "./helpers/mongo.js";
import { Completion } from "../src/models/completion.js";

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

async function createAuthedHousehold() {
  const signup = await app.inject({
    method: "POST",
    url: "/auth/signup",
    payload: {
      email: "chores@example.com",
      password: "password123",
      displayName: "Chore Admin",
    },
  });
  const { accessToken } = signup.json<{ accessToken: string }>();

  const create = await app.inject({
    method: "POST",
    url: "/households",
    headers: { authorization: `Bearer ${accessToken}` },
    payload: { name: "Chores Household" },
  });
  const {
    household: { id: householdId },
  } = create.json<{ household: { id: string } }>();

  return { accessToken, householdId };
}

describe("chore routes", () => {
  it("permanently deletes a chore and its completion history", async () => {
    const { accessToken, householdId } = await createAuthedHousehold();

    const roomRes = await app.inject({
      method: "POST",
      url: `/households/${householdId}/rooms`,
      headers: { authorization: `Bearer ${accessToken}` },
      payload: { name: "Kitchen" },
    });
    const { id: roomId } = roomRes.json<{ id: string }>();

    const choreRes = await app.inject({
      method: "POST",
      url: `/households/${householdId}/chores`,
      headers: { authorization: `Bearer ${accessToken}` },
      payload: {
        roomId,
        title: "Wipe counters",
        recurrence: { kind: "daily" },
        points: 1,
      },
    });
    const { id: choreId } = choreRes.json<{ id: string }>();

    const completeRes = await app.inject({
      method: "POST",
      url: `/households/${householdId}/chores/${choreId}/complete`,
      headers: { authorization: `Bearer ${accessToken}` },
      payload: { tz: "UTC" },
    });
    expect(completeRes.statusCode).toBe(201);

    const deleteRes = await app.inject({
      method: "DELETE",
      url: `/households/${householdId}/chores/${choreId}`,
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(deleteRes.statusCode).toBe(204);

    const listRes = await app.inject({
      method: "GET",
      url: `/households/${householdId}/chores?includeArchived=true`,
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(listRes.json<Array<{ id: string }>>()).toEqual([]);
    await expect(Completion.countDocuments({ householdId, choreId })).resolves.toBe(0);
  });
});
