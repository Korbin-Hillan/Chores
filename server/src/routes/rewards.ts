import type { FastifyInstance } from "fastify";
import { Types } from "mongoose";
import { z } from "zod";
import { Chore } from "../models/chore.js";
import { Completion } from "../models/completion.js";
import { HouseholdMember } from "../models/householdMember.js";
import { Reward, toSafeReward } from "../models/reward.js";
import { RewardRedemption, toSafeRewardRedemption } from "../models/rewardRedemption.js";
import { User } from "../models/user.js";
import { requireAuth } from "../middleware/requireAuth.js";
import { requireMembership } from "../middleware/requireMembership.js";
import { AppError } from "../utils/errors.js";

const rewardBody = z.object({
  title: z.string().min(1).max(80).trim(),
  description: z.string().max(500).optional(),
  costPoints: z.number().int().min(1).max(100_000),
});

const updateRewardBody = rewardBody.partial().extend({
  archived: z.boolean().optional(),
});

const rejectBody = z.object({
  rejectionReason: z.string().max(240).optional(),
});

export async function rewardRoutes(app: FastifyInstance): Promise<void> {
  app.addHook("preHandler", requireAuth);
  app.addHook("preHandler", requireMembership);

  app.get("/", async (request) => {
    const { householdId } = request.params as { householdId: string };
    const query = request.query as { includeArchived?: string };
    const filter: Record<string, unknown> = { householdId };
    if (query.includeArchived !== "true") filter["archived"] = false;

    const [rewards, balance] = await Promise.all([
      Reward.find(filter).sort({ costPoints: 1, createdAt: -1 }),
      getPointBalance(householdId, request.user.userId),
    ]);

    return {
      balance,
      rewards: rewards.map((reward) => ({
        ...toSafeReward(reward),
        canRedeem: balance.availablePoints >= reward.costPoints && !reward.archived,
      })),
    };
  });

  app.post("/", async (request, reply) => {
    const { householdId } = request.params as { householdId: string };
    if (request.membership.role !== "admin") {
      throw new AppError(403, "FORBIDDEN", "Only the household admin can create rewards");
    }

    const body = rewardBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    const reward = await Reward.create({
      householdId,
      ...body.data,
      description: body.data.description ?? null,
      createdByUserId: request.user.userId,
    });
    return reply.status(201).send(toSafeReward(reward));
  });

  app.put("/:rewardId", async (request, reply) => {
    const { householdId, rewardId } = request.params as { householdId: string; rewardId: string };
    if (request.membership.role !== "admin") {
      throw new AppError(403, "FORBIDDEN", "Only the household admin can update rewards");
    }

    const body = updateRewardBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    const reward = await Reward.findOneAndUpdate(
      { _id: rewardId, householdId },
      { $set: { ...body.data, description: body.data.description ?? undefined } },
      { new: true },
    );
    if (!reward) throw new AppError(404, "NOT_FOUND", "Reward not found");
    return reply.send(toSafeReward(reward));
  });

  app.post("/:rewardId/redeem", async (request, reply) => {
    const { householdId, rewardId } = request.params as { householdId: string; rewardId: string };
    const reward = await Reward.findOne({ _id: rewardId, householdId, archived: false });
    if (!reward) throw new AppError(404, "NOT_FOUND", "Reward not found");

    const balance = await getPointBalance(householdId, request.user.userId);
    if (balance.availablePoints < reward.costPoints) {
      throw new AppError(400, "INSUFFICIENT_POINTS", "Not enough points to redeem this reward");
    }

    const redemption = await RewardRedemption.create({
      householdId,
      rewardId,
      requestedByUserId: request.user.userId,
      costPointsSnapshot: reward.costPoints,
      rewardTitleSnapshot: reward.title,
      status: "pending",
    });

    return reply.status(201).send(toSafeRewardRedemption(redemption));
  });

  app.get("/redemptions", async (request) => {
    const { householdId } = request.params as { householdId: string };
    const query = request.query as { status?: string; mine?: string };
    const filter: Record<string, unknown> = { householdId };

    if (query.status) filter["status"] = query.status;
    if (query.mine === "true") filter["requestedByUserId"] = request.user.userId;

    if (query.mine !== "true" && request.membership.role !== "admin" && request.membership.role !== "parent") {
      filter["requestedByUserId"] = request.user.userId;
    }

    const redemptions = await RewardRedemption.find(filter)
      .sort({ createdAt: -1 })
      .limit(100)
      .populate<{
        requestedByUserId: {
          _id: Types.ObjectId;
          displayName: string;
          avatarContentType?: string | null;
        };
      }>(
        "requestedByUserId",
        "displayName avatarContentType",
      );

    return redemptions.map((redemption) => ({
      id: redemption._id.toString(),
      householdId: redemption.householdId.toString(),
      rewardId: redemption.rewardId.toString(),
      requestedByUserId: populatedOrObjectIdToString(redemption.requestedByUserId),
      costPointsSnapshot: redemption.costPointsSnapshot,
      rewardTitleSnapshot: redemption.rewardTitleSnapshot,
      status: redemption.status,
      reviewedByUserId: redemption.reviewedByUserId?.toString() ?? null,
      reviewedAt: redemption.reviewedAt ? redemption.reviewedAt.toISOString() : null,
      rejectionReason: redemption.rejectionReason ?? null,
      createdAt: (redemption as unknown as { createdAt: Date }).createdAt.toISOString(),
      requestedBy: userSummaryFromPopulated(redemption.requestedByUserId),
    }));
  });

  app.post("/redemptions/:redemptionId/approve", async (request, reply) => {
    const { householdId, redemptionId } = request.params as {
      householdId: string;
      redemptionId: string;
    };
    if (request.membership.role !== "admin" && request.membership.role !== "parent") {
      throw new AppError(403, "FORBIDDEN", "Only a parent can approve rewards");
    }

    const redemption = await RewardRedemption.findOneAndUpdate(
      { _id: redemptionId, householdId, status: "pending" },
      {
        $set: {
          status: "approved",
          reviewedByUserId: request.user.userId,
          reviewedAt: new Date(),
          rejectionReason: null,
        },
      },
      { new: true },
    );
    if (!redemption) throw new AppError(404, "NOT_FOUND", "Pending redemption not found");
    return reply.send(toSafeRewardRedemption(redemption));
  });

  app.post("/redemptions/:redemptionId/reject", async (request, reply) => {
    const { householdId, redemptionId } = request.params as {
      householdId: string;
      redemptionId: string;
    };
    if (request.membership.role !== "admin" && request.membership.role !== "parent") {
      throw new AppError(403, "FORBIDDEN", "Only a parent can reject rewards");
    }

    const body = rejectBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    const redemption = await RewardRedemption.findOneAndUpdate(
      { _id: redemptionId, householdId, status: "pending" },
      {
        $set: {
          status: "rejected",
          reviewedByUserId: request.user.userId,
          reviewedAt: new Date(),
          rejectionReason: body.data.rejectionReason ?? null,
        },
      },
      { new: true },
    );
    if (!redemption) throw new AppError(404, "NOT_FOUND", "Pending redemption not found");
    return reply.send(toSafeRewardRedemption(redemption));
  });

  app.get("/balance/:userId", async (request) => {
    const { householdId, userId } = request.params as { householdId: string; userId: string };
    if (
      userId !== request.user.userId &&
      request.membership.role !== "admin" &&
      request.membership.role !== "parent"
    ) {
      throw new AppError(403, "FORBIDDEN", "You can only view your own reward balance");
    }

    const membership = await HouseholdMember.findOne({ householdId, userId });
    if (!membership) throw new AppError(404, "NOT_FOUND", "Member not found");
    return getPointBalance(householdId, userId);
  });
}

async function getPointBalance(
  householdId: string,
  userId: string,
): Promise<{
  earnedPoints: number;
  approvedRedemptionPoints: number;
  pendingRedemptionPoints: number;
  availablePoints: number;
}> {
  const householdObjectId = Types.ObjectId.createFromHexString(householdId);
  const userObjectId = Types.ObjectId.createFromHexString(userId);

  const [earned] = await Completion.aggregate<{ total: number }>([
    {
      $match: {
        householdId: householdObjectId,
        completedByUserId: userObjectId,
        $or: [{ reviewStatus: "approved" }, { reviewStatus: { $exists: false } }],
      },
    },
    {
      $lookup: {
        from: Chore.collection.name,
        localField: "choreId",
        foreignField: "_id",
        as: "chore",
      },
    },
    { $unwind: "$chore" },
    { $group: { _id: null, total: { $sum: "$chore.points" } } },
  ]);

  const redemptionTotals = await RewardRedemption.aggregate<{
    _id: "approved" | "pending";
    total: number;
  }>([
    {
      $match: {
        householdId: householdObjectId,
        requestedByUserId: userObjectId,
        status: { $in: ["approved", "pending"] },
      },
    },
    { $group: { _id: "$status", total: { $sum: "$costPointsSnapshot" } } },
  ]);

  const approvedRedemptionPoints =
    redemptionTotals.find((item) => item._id === "approved")?.total ?? 0;
  const pendingRedemptionPoints =
    redemptionTotals.find((item) => item._id === "pending")?.total ?? 0;
  const earnedPoints = earned?.total ?? 0;
  return {
    earnedPoints,
    approvedRedemptionPoints,
    pendingRedemptionPoints,
    availablePoints: Math.max(0, earnedPoints - approvedRedemptionPoints - pendingRedemptionPoints),
  };
}

function userSummaryFromPopulated(
  value: unknown,
): { id: string; displayName: string; hasAvatar: boolean } | null {
  if (!value || value instanceof Types.ObjectId) return null;
  const user = value as {
    _id?: Types.ObjectId;
    displayName?: string;
    avatarContentType?: string | null;
  };
  if (!user._id || !user.displayName) return null;
  return {
    id: user._id.toString(),
    displayName: user.displayName,
    hasAvatar: Boolean(user.avatarContentType),
  };
}

function populatedOrObjectIdToString(value: unknown): string {
  if (value instanceof Types.ObjectId) return value.toString();
  const user = value as { _id?: Types.ObjectId };
  return user._id?.toString() ?? "";
}
