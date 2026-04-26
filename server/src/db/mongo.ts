import mongoose from "mongoose";
import type { FastifyBaseLogger } from "fastify";

export async function connectMongo(uri: string, logger: FastifyBaseLogger): Promise<void> {
  mongoose.set("strictQuery", true);
  await mongoose.connect(uri);
  logger.info({ host: new URL(uri).host }, "Connected to MongoDB");
}

export async function disconnectMongo(): Promise<void> {
  await mongoose.disconnect();
}
