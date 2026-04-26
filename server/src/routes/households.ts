import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { Household, toSafeHousehold } from "../models/household.js";
import { HouseholdMember, toSafeMember } from "../models/householdMember.js";
import { User, toSafeUser } from "../models/user.js";
import { requireAuth } from "../middleware/requireAuth.js";
import { requireAdmin } from "../middleware/requireMembership.js";
import { encrypt, decrypt } from "../services/crypto.js";
import { validateApiKey } from "../services/openai.js";
import { generateInviteCode } from "../utils/inviteCode.js";
import { AppError } from "../utils/errors.js";

const createBody = z.object({ name: z.string().min(1).max(80).trim() });
const joinBody = z.object({ inviteCode: z.string().min(1) });
const openAIKeyBody = z.object({ key: z.string().min(1) });

export async function householdRoutes(app: FastifyInstance): Promise<void> {
  app.addHook("preHandler", requireAuth);

  app.post("/", async (request, reply) => {
    const body = createBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    let inviteCode: string;
    let attempts = 0;
    do {
      inviteCode = generateInviteCode();
      attempts++;
      if (attempts > 10) throw new AppError(500, "INTERNAL", "Failed to generate unique invite code");
    } while (await Household.findOne({ inviteCode }));

    const household = await Household.create({
      name: body.data.name,
      inviteCode,
      adminUserId: request.user.userId,
    });

    const membership = await HouseholdMember.create({
      householdId: household._id,
      userId: request.user.userId,
      role: "admin",
    });

    await User.findByIdAndUpdate(request.user.userId, {
      currentHouseholdId: household._id,
    });

    return reply.status(201).send({
      household: toSafeHousehold(household),
      membership: toSafeMember(membership),
    });
  });

  app.get("/me", async (request) => {
    const memberships = await HouseholdMember.find({ userId: request.user.userId });
    const householdIds = memberships.map((m) => m.householdId);
    const households = await Household.find({ _id: { $in: householdIds } });
    return households.map(toSafeHousehold);
  });

  app.get("/:id", async (request) => {
    const { id } = request.params as { id: string };
    const membership = await HouseholdMember.findOne({
      householdId: id,
      userId: request.user.userId,
    });
    if (!membership) throw new AppError(403, "FORBIDDEN", "Not a member of this household");

    const household = await Household.findById(id);
    if (!household) throw new AppError(404, "NOT_FOUND", "Household not found");

    const allMemberships = await HouseholdMember.find({ householdId: id });
    const userIds = allMemberships.map((m) => m.userId);
    const users = await User.find({ _id: { $in: userIds } });

    const members = allMemberships.map((m) => ({
      ...toSafeMember(m),
      displayName: users.find((u) => u._id.equals(m.userId))?.displayName ?? "Unknown",
    }));

    return { household: toSafeHousehold(household), members };
  });

  app.post("/join", async (request, reply) => {
    const body = joinBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    const household = await Household.findOne({
      inviteCode: body.data.inviteCode.toUpperCase(),
    });
    if (!household) throw new AppError(404, "NOT_FOUND", "Invalid invite code");

    const existing = await HouseholdMember.findOne({
      householdId: household._id,
      userId: request.user.userId,
    });
    if (existing) {
      return reply.send({
        household: toSafeHousehold(household),
        membership: toSafeMember(existing),
      });
    }

    const membership = await HouseholdMember.create({
      householdId: household._id,
      userId: request.user.userId,
      role: "member",
    });

    await User.findByIdAndUpdate(request.user.userId, {
      currentHouseholdId: household._id,
    });

    return reply.status(201).send({
      household: toSafeHousehold(household),
      membership: toSafeMember(membership),
    });
  });

  app.post("/:id/regenerate-invite", { preHandler: [requireAdmin] }, async (request) => {
    const { id } = request.params as { id: string };
    const household = await Household.findById(id);
    if (!household) throw new AppError(404, "NOT_FOUND", "Household not found");

    let inviteCode = generateInviteCode();
    let attempts = 0;
    while (await Household.findOne({ inviteCode, _id: { $ne: id } })) {
      inviteCode = generateInviteCode();
      if (++attempts > 10) throw new AppError(500, "INTERNAL", "Failed to generate unique code");
    }

    household.inviteCode = inviteCode;
    await household.save();
    return { inviteCode };
  });

  // OpenAI key management
  app.put("/:id/openai-key", { preHandler: [requireAdmin] }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const body = openAIKeyBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    const isValid = await validateApiKey(body.data.key);
    if (!isValid) throw new AppError(400, "VALIDATION_FAILED", "The OpenAI API key is invalid");

    const encrypted = encrypt(body.data.key);
    await Household.findByIdAndUpdate(id, {
      openAIKey: encrypted,
      openAIKeySetAt: new Date(),
    });

    return reply.status(204).send();
  });

  app.delete("/:id/openai-key", { preHandler: [requireAdmin] }, async (request, reply) => {
    const { id } = request.params as { id: string };
    await Household.findByIdAndUpdate(id, { openAIKey: null, openAIKeySetAt: null });
    return reply.status(204).send();
  });

  app.get("/:id/openai-key/status", async (request) => {
    const { id } = request.params as { id: string };
    const membership = await HouseholdMember.findOne({
      householdId: id,
      userId: request.user.userId,
    });
    if (!membership) throw new AppError(403, "FORBIDDEN", "Not a member of this household");

    const household = await Household.findById(id).select("openAIKey openAIKeySetAt");
    if (!household) throw new AppError(404, "NOT_FOUND", "Household not found");

    return {
      isSet: household.openAIKey != null,
      setAt: household.openAIKeySetAt ? household.openAIKeySetAt.toISOString() : null,
    };
  });

  // Helper used by generation routes: get decrypted key or throw
  app.decorate("getDecryptedOpenAIKey", async (householdId: string): Promise<string> => {
    const household = await Household.findById(householdId).select("openAIKey");
    if (!household?.openAIKey) {
      throw new AppError(400, "OPENAI_KEY_MISSING", "No OpenAI key set for this household");
    }
    return decrypt(household.openAIKey);
  });
}
