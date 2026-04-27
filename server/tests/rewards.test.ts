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

async function signUp(email: string, displayName: string) {
  const signup = await app.inject({
    method: "POST",
    url: "/auth/signup",
    payload: { email, password: "password123", displayName },
  });
  return signup.json<{ accessToken: string; user: { id: string } }>();
}

async function createHousehold(accessToken: string) {
  const create = await app.inject({
    method: "POST",
    url: "/households",
    headers: { authorization: `Bearer ${accessToken}` },
    payload: { name: "Rewards Household" },
  });
  return create.json<{ household: { id: string; inviteCode: string } }>().household;
}

describe("reward routes", () => {
  it("lets members redeem earned points and reserves pending redemptions", async () => {
    const admin = await signUp("admin@example.com", "Admin");
    const child = await signUp("child@example.com", "Child");
    const household = await createHousehold(admin.accessToken);

    const joinRes = await app.inject({
      method: "POST",
      url: "/households/join",
      headers: { authorization: `Bearer ${child.accessToken}` },
      payload: { inviteCode: household.inviteCode },
    });
    expect(joinRes.statusCode).toBe(201);

    const roomRes = await app.inject({
      method: "POST",
      url: `/households/${household.id}/rooms`,
      headers: { authorization: `Bearer ${admin.accessToken}` },
      payload: { name: "Kitchen" },
    });
    const { id: roomId } = roomRes.json<{ id: string }>();

    const choreRes = await app.inject({
      method: "POST",
      url: `/households/${household.id}/chores`,
      headers: { authorization: `Bearer ${admin.accessToken}` },
      payload: {
        roomId,
        title: "Unload dishwasher",
        recurrence: { kind: "none" },
        points: 100,
      },
    });
    const { id: choreId } = choreRes.json<{ id: string }>();

    const completeRes = await app.inject({
      method: "POST",
      url: `/households/${household.id}/chores/${choreId}/complete`,
      headers: { authorization: `Bearer ${child.accessToken}` },
      payload: { tz: "UTC" },
    });
    expect(completeRes.statusCode).toBe(201);

    const rewardRes = await app.inject({
      method: "POST",
      url: `/households/${household.id}/rewards`,
      headers: { authorization: `Bearer ${admin.accessToken}` },
      payload: {
        title: "30 min screen time",
        costPoints: 80,
      },
    });
    expect(rewardRes.statusCode).toBe(201);
    const { id: rewardId } = rewardRes.json<{ id: string }>();

    const listBeforeRedeem = await app.inject({
      method: "GET",
      url: `/households/${household.id}/rewards`,
      headers: { authorization: `Bearer ${child.accessToken}` },
    });
    expect(listBeforeRedeem.json<{ balance: { availablePoints: number } }>().balance.availablePoints).toBe(100);

    const redeemRes = await app.inject({
      method: "POST",
      url: `/households/${household.id}/rewards/${rewardId}/redeem`,
      headers: { authorization: `Bearer ${child.accessToken}` },
      payload: {},
    });
    expect(redeemRes.statusCode).toBe(201);
    const { id: redemptionId } = redeemRes.json<{ id: string }>();

    const listAfterRedeem = await app.inject({
      method: "GET",
      url: `/households/${household.id}/rewards`,
      headers: { authorization: `Bearer ${child.accessToken}` },
    });
    expect(
      listAfterRedeem.json<{
        balance: { availablePoints: number; pendingRedemptionPoints: number };
      }>().balance,
    ).toMatchObject({ availablePoints: 20, pendingRedemptionPoints: 80 });

    const approveRes = await app.inject({
      method: "POST",
      url: `/households/${household.id}/rewards/redemptions/${redemptionId}/approve`,
      headers: { authorization: `Bearer ${admin.accessToken}` },
      payload: {},
    });
    expect(approveRes.statusCode).toBe(200);
    expect(approveRes.json<{ status: string }>().status).toBe("approved");
  });

  it("prevents non-admins from creating rewards", async () => {
    const admin = await signUp("admin@example.com", "Admin");
    const child = await signUp("child@example.com", "Child");
    const household = await createHousehold(admin.accessToken);

    await app.inject({
      method: "POST",
      url: "/households/join",
      headers: { authorization: `Bearer ${child.accessToken}` },
      payload: { inviteCode: household.inviteCode },
    });

    const rewardRes = await app.inject({
      method: "POST",
      url: `/households/${household.id}/rewards`,
      headers: { authorization: `Bearer ${child.accessToken}` },
      payload: { title: "Allowance", costPoints: 50 },
    });
    expect(rewardRes.statusCode).toBe(403);
  });
});
