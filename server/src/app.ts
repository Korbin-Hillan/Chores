import Fastify from "fastify";
import cors from "@fastify/cors";
import helmet from "@fastify/helmet";
import jwtPlugin from "@fastify/jwt";
import rateLimit from "@fastify/rate-limit";
import { env } from "./config/env.js";
import { errorHandler } from "./middleware/errorHandler.js";
import { healthRoutes } from "./routes/health.js";
import { authRoutes } from "./routes/auth.js";
import { householdRoutes } from "./routes/households.js";
import { roomRoutes } from "./routes/rooms.js";
import { choreRoutes, feedRoutes } from "./routes/chores.js";
import { generationRoutes } from "./routes/generation.js";

export interface BuildAppOptions {
  skipMongo?: boolean;
}

// eslint-disable-next-line @typescript-eslint/explicit-function-return-type
export async function buildApp(options: BuildAppOptions = {}) {
  // Avoid `exactOptionalPropertyTypes` rejection by not assigning undefined to transport.
  const loggerBase = {
    level: env.LOG_LEVEL,
    redact: {
      paths: ["req.headers.authorization", "req.body.password", "req.body.key"],
      censor: "[REDACTED]",
    },
  };
  const loggerConfig =
    env.NODE_ENV === "development"
      ? {
          ...loggerBase,
          transport: {
            target: "pino-pretty",
            options: { colorize: true, translateTime: "SYS:HH:MM:ss" },
          },
        }
      : loggerBase;

  const app = Fastify({
    logger: loggerConfig,
    bodyLimit: env.BODY_LIMIT_BYTES,
  });

  await app.register(helmet);
  await app.register(cors, { origin: true });
  await app.register(rateLimit, { max: 200, timeWindow: "1 minute" });
  await app.register(jwtPlugin, {
    secret: env.JWT_SECRET,
    sign: { expiresIn: "15m" },
  });

  if (!options.skipMongo) {
    const { connectMongo } = await import("./db/mongo.js");
    await connectMongo(env.MONGO_URI, app.log);
  }

  // Cast to satisfy Fastify's overloaded setErrorHandler signature across server variants.
  app.setErrorHandler(errorHandler as Parameters<typeof app.setErrorHandler>[0]);

  await app.register(healthRoutes);
  await app.register(authRoutes, { prefix: "/auth" });
  await app.register(householdRoutes, { prefix: "/households" });
  await app.register(roomRoutes, { prefix: "/households/:householdId/rooms" });
  await app.register(choreRoutes, { prefix: "/households/:householdId/chores" });
  await app.register(feedRoutes, { prefix: "/households/:householdId" });
  await app.register(generationRoutes, { prefix: "/households/:householdId/generate" });

  return app;
}
