import "@fastify/jwt";
import type { HouseholdMemberDoc } from "../models/householdMember.js";

declare module "@fastify/jwt" {
  interface FastifyJWT {
    payload: { userId: string };
    user: { userId: string };
  }
}

declare module "fastify" {
  interface FastifyRequest {
    membership: HouseholdMemberDoc;
  }
}
