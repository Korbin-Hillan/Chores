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
    household: { id: householdId, inviteCode },
  } = create.json<{ household: { id: string; inviteCode: string } }>();

  return { accessToken, householdId, inviteCode };
}

async function signUp(email: string, displayName: string) {
  const signup = await app.inject({
    method: "POST",
    url: "/auth/signup",
    payload: {
      email,
      password: "password123",
      displayName,
    },
  });
  return signup.json<{ accessToken: string; user: { id: string } }>();
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

  it("rotates assignment after completion and snapshots the original assignee for feed", async () => {
    const { accessToken, householdId, inviteCode } = await createAuthedHousehold();
    const sarah = await signUp("sarah@example.com", "Sarah");

    const joinRes = await app.inject({
      method: "POST",
      url: "/households/join",
      headers: { authorization: `Bearer ${sarah.accessToken}` },
      payload: { inviteCode },
    });
    expect(joinRes.statusCode).toBe(201);

    const detailRes = await app.inject({
      method: "GET",
      url: `/households/${householdId}`,
      headers: { authorization: `Bearer ${accessToken}` },
    });
    const detail = detailRes.json<{
      members: Array<{ userId: string; displayName: string }>;
    }>();
    const tomId = detail.members.find((member) => member.displayName === "Chore Admin")?.userId;
    expect(tomId).toBeTruthy();

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
        title: "Dishes",
        recurrence: { kind: "daily" },
        points: 1,
        assignedToUserId: tomId,
        rotationMemberIds: [tomId, sarah.user.id],
      },
    });
    expect(choreRes.statusCode).toBe(201);
    const chore = choreRes.json<{ id: string; assignedToUserId: string }>();
    expect(chore.assignedToUserId).toBe(tomId);

    const completeRes = await app.inject({
      method: "POST",
      url: `/households/${householdId}/chores/${chore.id}/complete`,
      headers: { authorization: `Bearer ${sarah.accessToken}` },
      payload: { tz: "UTC" },
    });
    expect(completeRes.statusCode).toBe(201);
    expect(
      completeRes.json<{ completion: { assignedToUserIdAtCompletion: string } }>().completion
        .assignedToUserIdAtCompletion,
    ).toBe(tomId);

    const choresRes = await app.inject({
      method: "GET",
      url: `/households/${householdId}/chores`,
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(choresRes.json<Array<{ id: string; assignedToUserId: string }>>()[0]?.assignedToUserId).toBe(
      sarah.user.id,
    );

    const feedRes = await app.inject({
      method: "GET",
      url: `/households/${householdId}/feed`,
      headers: { authorization: `Bearer ${accessToken}` },
    });
    const feed = feedRes.json<
      Array<{
        completedBy: { displayName: string };
        assignedToAtCompletion: { displayName: string } | null;
      }>
    >();
    expect(feed[0]?.completedBy.displayName).toBe("Sarah");
    expect(feed[0]?.assignedToAtCompletion?.displayName).toBe("Chore Admin");
  });

  it("requires photo evidence only for chores that opt in", async () => {
    const { accessToken, householdId } = await createAuthedHousehold();

    const roomRes = await app.inject({
      method: "POST",
      url: `/households/${householdId}/rooms`,
      headers: { authorization: `Bearer ${accessToken}` },
      payload: { name: "Bathroom" },
    });
    const { id: roomId } = roomRes.json<{ id: string }>();

    const choreRes = await app.inject({
      method: "POST",
      url: `/households/${householdId}/chores`,
      headers: { authorization: `Bearer ${accessToken}` },
      payload: {
        roomId,
        title: "Mirror",
        recurrence: { kind: "none" },
        points: 1,
        requiresPhotoEvidence: true,
      },
    });
    const { id: choreId } = choreRes.json<{ id: string }>();

    const missingPhotoRes = await app.inject({
      method: "POST",
      url: `/households/${householdId}/chores/${choreId}/complete`,
      headers: { authorization: `Bearer ${accessToken}` },
      payload: { tz: "UTC" },
    });
    expect(missingPhotoRes.statusCode).toBe(400);
    expect(missingPhotoRes.json<{ error: { code: string } }>().error.code).toBe("PHOTO_REQUIRED");

    const completeRes = await app.inject({
      method: "POST",
      url: `/households/${householdId}/chores/${choreId}/complete`,
      headers: { authorization: `Bearer ${accessToken}` },
      payload: {
        tz: "UTC",
        photoBase64: Buffer.from("tiny-photo").toString("base64"),
        photoContentType: "image/jpeg",
      },
    });
    expect(completeRes.statusCode).toBe(201);
    expect(completeRes.json<{ completion: { hasPhoto: boolean } }>().completion.hasPhoto).toBe(true);
  });
});
