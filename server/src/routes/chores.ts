import type { FastifyInstance } from "fastify";
import { Types } from "mongoose";
import { z } from "zod";
import { Chore, toSafeChore, type ChoreDoc } from "../models/chore.js";
import { Completion, toSafeCompletion } from "../models/completion.js";
import { HouseholdMember, toSafeMember } from "../models/householdMember.js";
import { User } from "../models/user.js";
import { requireAuth } from "../middleware/requireAuth.js";
import { requireMembership } from "../middleware/requireMembership.js";
import { AppError } from "../utils/errors.js";

const recurrenceSchema = z.object({
  kind: z.enum(["none", "daily", "weekly", "monthly"]),
  weekdays: z.array(z.number().int().min(0).max(6)).optional(),
  dayOfMonth: z.number().int().min(1).max(31).optional(),
});

const createBody = z.object({
  roomId: z.string().min(1),
  title: z.string().min(1).max(80).trim(),
  description: z.string().max(500).optional(),
  recurrence: recurrenceSchema.default({ kind: "none" }),
  estimatedMinutes: z.number().int().min(1).max(240).optional(),
  points: z.number().int().min(1).max(100).default(1),
  assignedToUserId: z.string().nullable().optional(),
  rotationMemberIds: z.array(z.string()).default([]),
  requiresPhotoEvidence: z.boolean().default(false),
  requiresParentApproval: z.boolean().default(false),
});

const updateBody = createBody.omit({ roomId: true }).partial().extend({
  roomId: z.string().optional(),
  archived: z.boolean().optional(),
});

const completeBody = z.object({
  notes: z.string().max(500).optional(),
  tz: z.string().default("UTC"),
  photoBase64: z.string().max(420_000).optional(),
  photoContentType: z.enum(["image/jpeg", "image/png"]).optional(),
});

const reviewBody = z.object({
  rejectionReason: z.string().max(240).optional(),
});

type SafeChoreWithCompletion = ReturnType<typeof toSafeChore> & {
  lastCompletedAt: string | null;
};

export async function choreRoutes(app: FastifyInstance): Promise<void> {
  app.addHook("preHandler", requireAuth);
  app.addHook("preHandler", requireMembership);

  app.get("/", async (request) => {
    const { householdId } = request.params as { householdId: string };
    const query = request.query as { roomId?: string; includeArchived?: string };

    const filter: Record<string, unknown> = { householdId };
    if (query.roomId) filter["roomId"] = query.roomId;
    if (query.includeArchived !== "true") filter["archived"] = false;

    const chores = await Chore.find(filter).sort({ createdAt: -1 });
    return await withLatestCompletion(chores.map(toSafeChore), householdId);
  });

  app.post("/", async (request, reply) => {
    const { householdId } = request.params as { householdId: string };
    const body = createBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);
    const assignment = await normalizeAssignment(
      householdId,
      body.data.assignedToUserId ?? null,
      body.data.rotationMemberIds,
    );

    const chore = await Chore.create({
      householdId,
      ...body.data,
      ...assignment,
      createdByUserId: request.user.userId,
      source: "manual",
    });

    return reply.status(201).send(toSafeChore(chore));
  });

  app.put("/:choreId", async (request, reply) => {
    const { householdId, choreId } = request.params as { householdId: string; choreId: string };
    const body = updateBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);
    const updateData = { ...body.data };
    if ("assignedToUserId" in updateData || "rotationMemberIds" in updateData) {
      const existing = await Chore.findOne({ _id: choreId, householdId });
      if (!existing) throw new AppError(404, "NOT_FOUND", "Chore not found");
      const assignment = await normalizeAssignment(
        householdId,
        updateData.assignedToUserId === undefined
          ? existing.assignedToUserId?.toString() ?? null
          : updateData.assignedToUserId ?? null,
        updateData.rotationMemberIds === undefined
          ? (existing.rotationMemberIds ?? []).map((id) => id.toString())
          : updateData.rotationMemberIds,
      );
      updateData.assignedToUserId = assignment.assignedToUserId;
      updateData.rotationMemberIds = assignment.rotationMemberIds;
    }

    const chore = await Chore.findOneAndUpdate(
      { _id: choreId, householdId },
      { $set: updateData },
      { new: true },
    );
    if (!chore) throw new AppError(404, "NOT_FOUND", "Chore not found");
    return reply.send(toSafeChore(chore));
  });

  app.delete("/:choreId", async (request, reply) => {
    const { householdId, choreId } = request.params as { householdId: string; choreId: string };
    const result = await Chore.deleteOne({ _id: choreId, householdId });
    if (result.deletedCount === 0) throw new AppError(404, "NOT_FOUND", "Chore not found");

    await Completion.deleteMany({ householdId, choreId });
    return reply.status(204).send();
  });

  app.post("/:choreId/complete", async (request, reply) => {
    const { householdId, choreId } = request.params as { householdId: string; choreId: string };
    const body = completeBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    const chore = await Chore.findOne({ _id: choreId, householdId, archived: false });
    if (!chore) throw new AppError(404, "NOT_FOUND", "Chore not found");

    const membership = await HouseholdMember.findOne({
      householdId,
      userId: request.user.userId,
    });
    if (!membership) throw new AppError(403, "FORBIDDEN", "Not a member of this household");

    const photo = decodePhoto(body.data.photoBase64, body.data.photoContentType);
    if (chore.requiresPhotoEvidence && !photo) {
      throw new AppError(400, "PHOTO_REQUIRED", "This chore requires a photo to complete");
    }

    const assignedToUserIdAtCompletion = chore.assignedToUserId ?? null;
    const reviewStatus =
      chore.requiresParentApproval && membership.role === "member" ? "pending" : "approved";

    const completion = await Completion.create({
      choreId,
      householdId,
      completedByUserId: request.user.userId,
      notes: body.data.notes ?? null,
      assignedToUserIdAtCompletion,
      reviewStatus,
      photo: photo?.buffer ?? null,
      photoContentType: photo?.contentType ?? null,
      photoExpiresAt: photo ? new Date(Date.now() + 86_400_000) : null,
    });

    const now = new Date();
    const tz = body.data.tz;
    const todayStr = toLocalDateString(now, tz);
    let newStreak = membership.currentStreak;

    if (membership.lastCompletionAt) {
      const lastStr = toLocalDateString(membership.lastCompletionAt, tz);
      const yesterdayStr = toLocalDateString(new Date(now.getTime() - 86_400_000), tz);

      if (lastStr === todayStr) {
        // same day — no streak change
      } else if (lastStr === yesterdayStr) {
        newStreak += 1;
      } else {
        newStreak = 1;
      }
    } else {
      newStreak = 1;
    }

    membership.currentStreak = newStreak;
    membership.longestStreak = Math.max(membership.longestStreak, newStreak);
    membership.lastCompletionAt = now;
    await membership.save();
    await advanceRotation(chore, householdId);

    return reply.status(201).send({
      completion: toSafeCompletion(completion),
      membership: toSafeMember(membership),
    });
  });

  app.get("/:choreId/completions", async (request) => {
    const { householdId, choreId } = request.params as { householdId: string; choreId: string };
    const { limit = "20" } = request.query as { limit?: string };
    const limitNum = Math.min(parseInt(limit, 10) || 20, 100);

    const chore = await Chore.findOne({ _id: choreId, householdId });
    if (!chore) throw new AppError(404, "NOT_FOUND", "Chore not found");
    await cleanupExpiredCompletionPhotos(householdId);

    const completions = await Completion.find({ householdId, choreId })
      .sort({ completedAt: -1 })
      .limit(limitNum)
      .populate<{ completedByUserId: { _id: Types.ObjectId; displayName: string } }>(
        "completedByUserId",
        "displayName",
      )
      .populate<{ assignedToUserIdAtCompletion: { _id: Types.ObjectId; displayName: string } }>(
        "assignedToUserIdAtCompletion",
        "displayName",
      );

    return completions.map((completion) => ({
      id: completion._id.toString(),
      completedAt: completion.completedAt.toISOString(),
      notes: completion.notes ?? null,
      reviewStatus: completion.reviewStatus ?? "approved",
      hasPhoto: Boolean(
        completion.photoContentType &&
          completion.photoExpiresAt &&
          completion.photoExpiresAt > new Date(),
      ),
      assignedToUserIdAtCompletion: completion.assignedToUserIdAtCompletion?.toString() ?? null,
      completedBy: {
        id: completion.completedByUserId._id.toString(),
        displayName: completion.completedByUserId.displayName,
      },
    }));
  });
}

// Feed and leaderboard live here but are registered under a different prefix in app.ts
export async function feedRoutes(app: FastifyInstance): Promise<void> {
  app.addHook("preHandler", requireAuth);
  app.addHook("preHandler", requireMembership);

  app.get("/feed", async (request) => {
    const { householdId } = request.params as { householdId: string };
    const { limit = "50" } = request.query as { limit?: string };
    const limitNum = Math.min(parseInt(limit, 10) || 50, 100);
    await cleanupExpiredCompletionPhotos(householdId);

    const completions = await Completion.find({ householdId })
      .sort({ completedAt: -1 })
      .limit(limitNum)
      .populate<{ choreId: Parameters<typeof toSafeChore>[0] }>("choreId")
      .populate<{ completedByUserId: { _id: Types.ObjectId; displayName: string } }>(
        "completedByUserId",
        "displayName",
      )
      .populate<{ assignedToUserIdAtCompletion: { _id: Types.ObjectId; displayName: string } }>(
        "assignedToUserIdAtCompletion",
        "displayName",
      );

    return completions.map((c) => ({
      id: c._id.toString(),
      completedAt: c.completedAt.toISOString(),
      notes: c.notes ?? null,
      reviewStatus: c.reviewStatus ?? "approved",
      hasPhoto: Boolean(c.photoContentType && c.photoExpiresAt && c.photoExpiresAt > new Date()),
      assignedToUserIdAtCompletion: c.assignedToUserIdAtCompletion?.toString() ?? null,
      assignedToAtCompletion: userSummaryFromPopulated(c.assignedToUserIdAtCompletion),
      chore: c.choreId ? toSafeChore(c.choreId) : null,
      completedBy: {
        id: c.completedByUserId._id.toString(),
        displayName: c.completedByUserId.displayName,
      },
    }));
  });

  app.get("/completions/:completionId/photo", async (request, reply) => {
    const { householdId, completionId } = request.params as {
      householdId: string;
      completionId: string;
    };
    await cleanupExpiredCompletionPhotos(householdId);
    const completion = await Completion.findOne({ _id: completionId, householdId }).select(
      "+photo photoContentType photoExpiresAt",
    );
    if (!completion?.photo || !completion.photoContentType) {
      throw new AppError(404, "NOT_FOUND", "Photo not found");
    }
    if (completion.photoExpiresAt && completion.photoExpiresAt <= new Date()) {
      completion.photo = null;
      completion.photoContentType = null;
      completion.photoExpiresAt = null;
      await completion.save();
      throw new AppError(404, "NOT_FOUND", "Photo not found");
    }
    return reply.type(completion.photoContentType).send(completion.photo);
  });

  app.get("/completions/pending", async (request) => {
    const { householdId } = request.params as { householdId: string };
    if (request.membership.role !== "admin" && request.membership.role !== "parent") {
      throw new AppError(403, "FORBIDDEN", "Only a parent can review completions");
    }
    await cleanupExpiredCompletionPhotos(householdId);

    const completions = await Completion.find({ householdId, reviewStatus: "pending" })
      .sort({ completedAt: -1 })
      .limit(50)
      .populate<{ choreId: Parameters<typeof toSafeChore>[0] }>("choreId")
      .populate<{ completedByUserId: { _id: Types.ObjectId; displayName: string } }>(
        "completedByUserId",
        "displayName",
      );

    return completions.map((c) => ({
      id: c._id.toString(),
      completedAt: c.completedAt.toISOString(),
      notes: c.notes ?? null,
      reviewStatus: c.reviewStatus ?? "approved",
      hasPhoto: Boolean(c.photoContentType && c.photoExpiresAt && c.photoExpiresAt > new Date()),
      assignedToUserIdAtCompletion: c.assignedToUserIdAtCompletion?.toString() ?? null,
      chore: c.choreId ? toSafeChore(c.choreId) : null,
      completedBy: {
        id: c.completedByUserId._id.toString(),
        displayName: c.completedByUserId.displayName,
      },
    }));
  });

  app.post("/completions/:completionId/approve", async (request, reply) => {
    const { householdId, completionId } = request.params as {
      householdId: string;
      completionId: string;
    };
    if (request.membership.role !== "admin" && request.membership.role !== "parent") {
      throw new AppError(403, "FORBIDDEN", "Only a parent can review completions");
    }
    const completion = await Completion.findOneAndUpdate(
      { _id: completionId, householdId, reviewStatus: "pending" },
      {
        $set: {
          reviewStatus: "approved",
          reviewedByUserId: request.user.userId,
          reviewedAt: new Date(),
          rejectionReason: null,
        },
      },
      { new: true },
    );
    if (!completion) throw new AppError(404, "NOT_FOUND", "Pending completion not found");
    return reply.send(toSafeCompletion(completion));
  });

  app.post("/completions/:completionId/reject", async (request, reply) => {
    const { householdId, completionId } = request.params as {
      householdId: string;
      completionId: string;
    };
    if (request.membership.role !== "admin" && request.membership.role !== "parent") {
      throw new AppError(403, "FORBIDDEN", "Only a parent can review completions");
    }
    const body = reviewBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);
    const completion = await Completion.findOneAndUpdate(
      { _id: completionId, householdId, reviewStatus: "pending" },
      {
        $set: {
          reviewStatus: "rejected",
          reviewedByUserId: request.user.userId,
          reviewedAt: new Date(),
          rejectionReason: body.data.rejectionReason ?? null,
        },
      },
      { new: true },
    );
    if (!completion) throw new AppError(404, "NOT_FOUND", "Pending completion not found");
    return reply.send(toSafeCompletion(completion));
  });

  app.get("/leaderboard", async (request) => {
    const { householdId } = request.params as { householdId: string };
    const { period = "week" } = request.query as { period?: "week" | "month" | "all" };

    const since = new Date();
    if (period === "week") since.setDate(since.getDate() - 7);
    else if (period === "month") since.setMonth(since.getMonth() - 1);
    else since.setFullYear(2000);

    const aggregated = await Completion.aggregate<{
      _id: Types.ObjectId;
      completionCount: number;
    }>([
      {
        $match: {
          householdId: Types.ObjectId.createFromHexString(householdId),
          completedAt: { $gte: since },
        },
      },
      { $group: { _id: "$completedByUserId", completionCount: { $sum: 1 } } },
      { $sort: { completionCount: -1 } },
    ]);

    const memberIds = aggregated.map((a) => a._id);
    const [memberships, users] = await Promise.all([
      HouseholdMember.find({ householdId, userId: { $in: memberIds } }),
      User.find({ _id: { $in: memberIds } }).select("displayName"),
    ]);

    return aggregated.map((a) => {
      const membership = memberships.find((m) => m.userId.equals(a._id));
      const user = users.find((u) => u._id.equals(a._id));
      return {
        userId: a._id.toString(),
        displayName: user?.displayName ?? "Unknown",
        completionCount: a.completionCount,
        currentStreak: membership?.currentStreak ?? 0,
        longestStreak: membership?.longestStreak ?? 0,
      };
    });
  });
}

async function cleanupExpiredCompletionPhotos(householdId: string): Promise<void> {
  await Completion.updateMany(
    { householdId, photoExpiresAt: { $lte: new Date() } },
    { $set: { photo: null, photoContentType: null, photoExpiresAt: null } },
  );
}

async function normalizeAssignment(
  householdId: string,
  assignedToUserId: string | null,
  rotationMemberIds: string[],
): Promise<{ assignedToUserId: string | null; rotationMemberIds: string[] }> {
  const normalizedRotation = Array.from(new Set(rotationMemberIds.filter(Boolean)));
  const idsToCheck = Array.from(
    new Set([...(assignedToUserId ? [assignedToUserId] : []), ...normalizedRotation]),
  );
  if (idsToCheck.length === 0) {
    return { assignedToUserId: null, rotationMemberIds: [] };
  }

  const members = await HouseholdMember.find({ householdId, userId: { $in: idsToCheck } }).select(
    "userId",
  );
  const validIds = new Set(members.map((member) => member.userId.toString()));
  const invalidIds = idsToCheck.filter((id) => !validIds.has(id));
  if (invalidIds.length > 0) {
    throw new AppError(400, "VALIDATION_FAILED", "Assigned users must be household members");
  }

  const validRotation = normalizedRotation.filter((id) => validIds.has(id));
  return {
    assignedToUserId: assignedToUserId && validIds.has(assignedToUserId) ? assignedToUserId : null,
    rotationMemberIds: validRotation,
  };
}

function decodePhoto(
  photoBase64: string | undefined,
  photoContentType: "image/jpeg" | "image/png" | undefined,
): { buffer: Buffer; contentType: string } | null {
  if (!photoBase64 && !photoContentType) return null;
  if (!photoBase64 || !photoContentType) {
    throw new AppError(400, "VALIDATION_FAILED", "Photo content and type are both required");
  }
  const buffer = Buffer.from(photoBase64, "base64");
  if (buffer.length > 300_000) {
    throw new AppError(400, "PHOTO_TOO_LARGE", "Photo evidence must be 300 KB or smaller");
  }
  return { buffer, contentType: photoContentType };
}

async function advanceRotation(chore: ChoreDoc | null, householdId: string): Promise<void> {
  if (!chore || chore.rotationMemberIds.length === 0) return;
  const currentRotation = chore.rotationMemberIds.map((id) => id.toString());
  const activeMembers = await HouseholdMember.find({
    householdId,
    userId: { $in: currentRotation },
  }).select("userId");
  const activeIds = new Set(activeMembers.map((member) => member.userId.toString()));
  const rotation = currentRotation.filter((id) => activeIds.has(id));

  chore.rotationMemberIds = rotation.map((id) => Types.ObjectId.createFromHexString(id));
  if (rotation.length === 0) {
    chore.assignedToUserId = null;
    await chore.save();
    return;
  }

  const currentId = chore.assignedToUserId?.toString();
  const currentIndex = currentId ? rotation.indexOf(currentId) : -1;
  const nextIndex = currentIndex >= 0 ? (currentIndex + 1) % rotation.length : 0;
  const nextId = rotation[nextIndex];
  if (!nextId) return;
  chore.assignedToUserId = Types.ObjectId.createFromHexString(nextId);
  await chore.save();
}

function userSummaryFromPopulated(
  value: unknown,
): { id: string; displayName: string } | null {
  if (!value || value instanceof Types.ObjectId) return null;
  const user = value as { _id?: Types.ObjectId; displayName?: string };
  if (!user._id || !user.displayName) return null;
  return { id: user._id.toString(), displayName: user.displayName };
}

function toLocalDateString(date: Date, tz: string): string {
  try {
    return date.toLocaleDateString("en-CA", { timeZone: tz }); // YYYY-MM-DD
  } catch {
    return date.toLocaleDateString("en-CA", { timeZone: "UTC" });
  }
}

async function withLatestCompletion(
  chores: Array<ReturnType<typeof toSafeChore>>,
  householdId: string,
): Promise<SafeChoreWithCompletion[]> {
  if (chores.length === 0) return [];

  const choreIds = chores.map((chore) => Types.ObjectId.createFromHexString(chore.id));
  const latestCompletions = await Completion.aggregate<{
    _id: Types.ObjectId;
    lastCompletedAt: Date;
  }>([
    {
      $match: {
        householdId: Types.ObjectId.createFromHexString(householdId),
        choreId: { $in: choreIds },
      },
    },
    { $sort: { completedAt: -1 } },
    { $group: { _id: "$choreId", lastCompletedAt: { $first: "$completedAt" } } },
  ]);

  const latestByChoreId = new Map(
    latestCompletions.map((completion) => [
      completion._id.toHexString(),
      completion.lastCompletedAt.toISOString(),
    ]),
  );

  return chores.map((chore) => ({
    ...chore,
    lastCompletedAt: latestByChoreId.get(chore.id) ?? null,
  }));
}
