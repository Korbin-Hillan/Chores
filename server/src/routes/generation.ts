import { createHash } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { Household } from "../models/household.js";
import { Room } from "../models/room.js";
import { Chore, toSafeChore } from "../models/chore.js";
import { GenerationJob } from "../models/generationJob.js";
import type { ChoreDraft } from "../models/generationJob.js";
import { decrypt } from "../services/crypto.js";
import { generateChoresFromText, generateChoresFromImage } from "../services/openai.js";
import { requireAuth } from "../middleware/requireAuth.js";
import { requireMembership } from "../middleware/requireMembership.js";
import { AppError } from "../utils/errors.js";

const MAX_IMAGE_BASE64_BYTES = 4 * 1024 * 1024 * (4 / 3); // ~5.5 MB base64 of a 4 MB image

const textGenBody = z.object({
  prompt: z.string().min(1).max(1000),
  roomId: z.string().optional(),
});

const imageGenBody = z.object({
  imageBase64: z.string().min(1),
  mimeType: z.enum(["image/jpeg", "image/png", "image/webp"]),
  roomId: z.string().optional(),
});

const acceptBody = z.object({
  acceptedIndices: z.array(z.number().int().min(0)),
});

async function getDecryptedKey(householdId: string): Promise<string> {
  const household = await Household.findById(householdId).select("openAIKey");
  if (!household?.openAIKey) {
    throw new AppError(400, "OPENAI_KEY_MISSING", "No OpenAI key set for this household. Ask your admin to add one in Settings.");
  }
  return decrypt(household.openAIKey);
}

async function findOrCreateRoom(
  householdId: string,
  roomName: string,
  existingRooms: Array<{ id: string; name: string }>,
): Promise<string> {
  const normalized = roomName.toLowerCase().trim();
  const match = existingRooms.find((r) => r.name.toLowerCase() === normalized);
  if (match) return match.id;

  const newRoom = await Room.create({ householdId, name: roomName });
  existingRooms.push({ id: newRoom._id.toString(), name: newRoom.name });
  return newRoom._id.toString();
}

export async function generationRoutes(app: FastifyInstance): Promise<void> {
  app.addHook("preHandler", requireAuth);
  app.addHook("preHandler", requireMembership);

  app.post("/text", async (request, reply) => {
    const { householdId } = request.params as { householdId: string };
    const body = textGenBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    const apiKey = await getDecryptedKey(householdId);
    const existingRooms = (await Room.find({ householdId, archived: false }).select("name")).map(
      (r) => ({ id: r._id.toString(), name: r.name }),
    );

    const { chores, model, tokenUsage } = await generateChoresFromText(
      apiKey,
      body.data.prompt,
      existingRooms.map((r) => r.name),
    );

    const job = await GenerationJob.create({
      householdId,
      requestedByUserId: request.user.userId,
      inputType: "text",
      inputSummary: body.data.prompt.slice(0, 200),
      model,
      tokenUsage,
      suggestedChores: chores,
    });

    return reply.status(201).send({
      jobId: job._id.toString(),
      suggestedChores: chores,
    });
  });

  app.post("/image", async (request, reply) => {
    const { householdId } = request.params as { householdId: string };
    const body = imageGenBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    if (body.data.imageBase64.length > MAX_IMAGE_BASE64_BYTES) {
      throw new AppError(400, "VALIDATION_FAILED", "Image too large. Please use an image under 4 MB.");
    }

    const apiKey = await getDecryptedKey(householdId);
    const existingRooms = (await Room.find({ householdId, archived: false }).select("name")).map(
      (r) => ({ id: r._id.toString(), name: r.name }),
    );

    const { chores, model, tokenUsage } = await generateChoresFromImage(
      apiKey,
      body.data.imageBase64,
      body.data.mimeType,
      existingRooms.map((r) => r.name),
    );

    const imageHash = createHash("sha256").update(body.data.imageBase64).digest("hex");

    const job = await GenerationJob.create({
      householdId,
      requestedByUserId: request.user.userId,
      inputType: "image",
      inputSummary: `image:${imageHash.slice(0, 16)}`,
      model,
      tokenUsage,
      suggestedChores: chores,
    });

    return reply.status(201).send({
      jobId: job._id.toString(),
      suggestedChores: chores,
    });
  });

  app.post("/:jobId/accept", async (request, reply) => {
    const { householdId, jobId } = request.params as { householdId: string; jobId: string };
    const body = acceptBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    const job = await GenerationJob.findOne({ _id: jobId, householdId });
    if (!job) throw new AppError(404, "NOT_FOUND", "Generation job not found");

    const existingRooms = (await Room.find({ householdId, archived: false }).select("name")).map(
      (r) => ({ id: r._id.toString(), name: r.name }),
    );

    const accepted: ChoreDraft[] = body.data.acceptedIndices
      .filter((i) => i >= 0 && i < job.suggestedChores.length)
      .map((i) => job.suggestedChores[i] as ChoreDraft);

    const createdChores = await Promise.all(
      accepted.map(async (draft) => {
        const roomId = await findOrCreateRoom(householdId, draft.suggestedRoomName, existingRooms);
        return Chore.create({
          householdId,
          roomId,
          title: draft.title,
          description: draft.description ?? null,
          recurrence: draft.recurrence,
          estimatedMinutes: draft.estimatedMinutes ?? null,
          createdByUserId: request.user.userId,
          source: job.inputType === "text" ? "ai_text" : "ai_image",
        });
      }),
    );

    job.createdChoreIds = createdChores.map((c) => c._id);
    await job.save();

    return reply.status(201).send(createdChores.map(toSafeChore));
  });
}
