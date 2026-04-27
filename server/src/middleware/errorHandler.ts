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

  if (error.code === "FST_ERR_CTP_BODY_TOO_LARGE") {
    reply.status(413).send({
      error: {
        code: "VALIDATION_FAILED",
        message: "Request body is too large. If you're uploading a room photo, use an image under 4 MB.",
        details: {},
      },
    });
    return;
  }

  if (error.statusCode === 429) {
    reply.status(429).send({
      error: {
        code: "RATE_LIMIT_EXCEEDED",
        message: error.message,
        details: {},
      },
    });
    return;
  }

  request.log.error({ err: error }, "Unhandled error");
  reply.status(500).send({
    error: { code: "INTERNAL", message: "Internal server error", details: {} },
  });
}
