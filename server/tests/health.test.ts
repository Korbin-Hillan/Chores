import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";

// Set required env vars before importing modules that read env at load time.
process.env.MONGO_URI ??= "mongodb://placeholder/test";
process.env.JWT_SECRET ??= "test_jwt_secret_at_least_thirty_two_characters_long_xx";
process.env.KEY_ENCRYPTION_SECRET ??=
  "test_key_encryption_secret_at_least_thirty_two_chars_xx";

let app: FastifyInstance;

beforeAll(async () => {
  const { buildApp } = await import("../src/app.js");
  app = await buildApp({ skipMongo: true });
});

afterAll(async () => {
  await app.close();
});

describe("GET /health", () => {
  it("returns ok with a timestamp", async () => {
    const res = await app.inject({ method: "GET", url: "/health" });
    expect(res.statusCode).toBe(200);
    const body = res.json() as { status: string; timestamp: string };
    expect(body.status).toBe("ok");
    expect(new Date(body.timestamp).toString()).not.toBe("Invalid Date");
  });
});
