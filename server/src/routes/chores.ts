import type { FastifyInstance } from "fastify";
import { Types } from "mongoose";
import { z } from "zod";
import { Chore, toSafeChore } from "../models/chore.js";
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
});

const updateBody = createBody.omit({ roomId: true }).partial().extend({
  roomId: z.string().optional(),
  archived: z.boolean().optional(),
});

const completeBody = z.object({
  notes: z.string().max(500).optional(),
  tz: z.string().default("UTC"),
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

    const chore = await Chore.create({
      householdId,
      ...body.data,
      createdByUserId: request.user.userId,
      source: "manual",
    });

    return reply.status(201).send(toSafeChore(chore));
  });

  app.put("/:choreId", async (request, reply) => {
    const { householdId, choreId } = request.params as { householdId: string; choreId: string };
    const body = updateBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    const chore = await Chore.findOneAndUpdate(
      { _id: choreId, householdId },
      { $set: body.data },
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

    const completion = await Completion.create({
      choreId,
      householdId,
      completedByUserId: request.user.userId,
      notes: body.data.notes ?? null,
    });

    const membership = await HouseholdMember.findOne({
      householdId,
      userId: request.user.userId,
    });
    if (!membership) throw new AppError(403, "FORBIDDEN", "Not a member of this household");

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

    const completions = await Completion.find({ householdId, choreId })
      .sort({ completedAt: -1 })
      .limit(limitNum)
      .populate<{ completedByUserId: { _id: Types.ObjectId; displayName: string } }>(
        "completedByUserId",
        "displayName",
      );

    return completions.map((completion) => ({
      id: completion._id.toString(),
      completedAt: completion.completedAt.toISOString(),
      notes: completion.notes ?? null,
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

    const completions = await Completion.find({ householdId })
      .sort({ completedAt: -1 })
      .limit(limitNum)
      .populate<{ choreId: Parameters<typeof toSafeChore>[0] }>("choreId")
      .populate<{ completedByUserId: { _id: Types.ObjectId; displayName: string } }>(
        "completedByUserId",
        "displayName",
      );

    return completions.map((c) => ({
      id: c._id.toString(),
      completedAt: c.completedAt.toISOString(),
      notes: c.notes ?? null,
      chore: c.choreId ? toSafeChore(c.choreId) : null,
      completedBy: {
        id: c.completedByUserId._id.toString(),
        displayName: c.completedByUserId.displayName,
      },
    }));
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
