import type { FastifyError, FastifyReply, FastifyRequest } from "fastify";
import { AppError } from "../utils/errors.js";

export function errorHandler(
  error: FastifyError,
  request: FastifyRequest,
  reply: FastifyReply,
): void {
  if (error instanceof AppError) {
    reply.status(error.statusCode).send({
      error: { code: error.code, message: error.message, details: error.details ?? {} },
    });
    return;
  }

  if (error.validation) {
    reply.status(400).send({
      error: {
        code: "VALIDATION_FAILED",
        message: error.message,
        details: { issues: error.validation },
      },
    });
    return;
  }

  request.log.error({ err: error }, "Unhandled error");
  reply.status(500).send({
    error: { code: "INTERNAL", message: "Internal server error", details: {} },
  });
}
