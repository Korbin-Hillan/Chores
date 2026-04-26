import type { FastifyReply, FastifyRequest } from "fastify";
import { HouseholdMember } from "../models/householdMember.js";
import { AppError } from "../utils/errors.js";

function getHouseholdIdFromParams(request: FastifyRequest): string | undefined {
  const params = request.params as { householdId?: string; id?: string };
  return params.householdId ?? params.id;
}

export async function requireMembership(
  request: FastifyRequest,
  reply: FastifyReply,
): Promise<void> {
  const householdId = getHouseholdIdFromParams(request);
  if (!householdId) throw new AppError(400, "VALIDATION_FAILED", "householdId param is required");

  const membership = await HouseholdMember.findOne({
    householdId,
    userId: request.user.userId,
  });

  if (!membership) {
    throw new AppError(403, "FORBIDDEN", "You are not a member of this household");
  }

  request.membership = membership;
  void reply;
}

export async function requireAdmin(
  request: FastifyRequest,
  reply: FastifyReply,
): Promise<void> {
  await requireMembership(request, reply);
  if (request.membership.role !== "admin") {
    throw new AppError(403, "FORBIDDEN", "Only the household admin can perform this action");
  }
}
