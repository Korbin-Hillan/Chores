import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { Room, toSafeRoom } from "../models/room.js";
import { requireAuth } from "../middleware/requireAuth.js";
import { requireMembership } from "../middleware/requireMembership.js";
import { AppError } from "../utils/errors.js";

const createBody = z.object({
  name: z.string().min(1).max(60).trim(),
  icon: z.string().max(50).optional(),
});

const updateBody = createBody.partial().extend({
  archived: z.boolean().optional(),
});

export async function roomRoutes(app: FastifyInstance): Promise<void> {
  app.addHook("preHandler", requireAuth);
  app.addHook("preHandler", requireMembership);

  app.get("/", async (request) => {
    const { householdId } = request.params as { householdId: string };
    const query = request.query as { includeArchived?: string };
    const filter: Record<string, unknown> = { householdId };
    if (query.includeArchived !== "true") filter["archived"] = false;

    const rooms = await Room.find(filter).sort({ name: 1 });
    return rooms.map(toSafeRoom);
  });

  app.post("/", async (request, reply) => {
    const { householdId } = request.params as { householdId: string };
    const body = createBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    const room = await Room.create({
      householdId,
      name: body.data.name,
      icon: body.data.icon ?? null,
    });

    return reply.status(201).send(toSafeRoom(room));
  });

  app.put("/:roomId", async (request, reply) => {
    const { householdId, roomId } = request.params as { householdId: string; roomId: string };
    const body = updateBody.safeParse(request.body);
    if (!body.success) throw new AppError(400, "VALIDATION_FAILED", body.error.message);

    const room = await Room.findOneAndUpdate(
      { _id: roomId, householdId },
      { $set: body.data },
      { new: true },
    );
    if (!room) throw new AppError(404, "NOT_FOUND", "Room not found");

    return reply.send(toSafeRoom(room));
  });
}
