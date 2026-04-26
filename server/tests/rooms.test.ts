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

async function createAuthedHousehold() {
  const signup = await app.inject({
    method: "POST",
    url: "/auth/signup",
    payload: {
      email: "rooms@example.com",
      password: "password123",
      displayName: "Room Admin",
    },
  });
  const { accessToken } = signup.json<{ accessToken: string }>();

  const create = await app.inject({
    method: "POST",
    url: "/households",
    headers: { authorization: `Bearer ${accessToken}` },
    payload: { name: "Rooms Household" },
  });
  const {
    household: { id: householdId },
  } = create.json<{ household: { id: string } }>();

  return { accessToken, householdId };
}

describe("room routes", () => {
  it("allows duplicate room names within the same household", async () => {
    const { accessToken, householdId } = await createAuthedHousehold();

    const first = await app.inject({
      method: "POST",
      url: `/households/${householdId}/rooms`,
      headers: { authorization: `Bearer ${accessToken}` },
      payload: { name: "Bedroom" },
    });
    const second = await app.inject({
      method: "POST",
      url: `/households/${householdId}/rooms`,
      headers: { authorization: `Bearer ${accessToken}` },
      payload: { name: "Bedroom" },
    });

    expect(first.statusCode).toBe(201);
    expect(second.statusCode).toBe(201);
    expect(first.json<{ id: string }>().id).not.toBe(second.json<{ id: string }>().id);
  });

  it("deletes an empty room", async () => {
    const { accessToken, householdId } = await createAuthedHousehold();

    const roomRes = await app.inject({
      method: "POST",
      url: `/households/${householdId}/rooms`,
      headers: { authorization: `Bearer ${accessToken}` },
      payload: { name: "Closet" },
    });
    const { id: roomId } = roomRes.json<{ id: string }>();

    const deleteRes = await app.inject({
      method: "DELETE",
      url: `/households/${householdId}/rooms/${roomId}`,
      headers: { authorization: `Bearer ${accessToken}` },
    });

    expect(deleteRes.statusCode).toBe(204);
  });

  it("rejects deleting a room that still has chores", async () => {
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
        recurrence: { kind: "weekly", weekdays: [1] },
        points: 1,
      },
    });
    expect(choreRes.statusCode).toBe(201);

    const deleteRes = await app.inject({
      method: "DELETE",
      url: `/households/${householdId}/rooms/${roomId}`,
      headers: { authorization: `Bearer ${accessToken}` },
    });

    expect(deleteRes.statusCode).toBe(400);
    expect(deleteRes.json<{ error: { message: string } }>().error.message).toContain(
      "Move, archive, or delete the chores in this room before deleting it.",
    );
  });
});
