import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import type { FastifyInstance } from "fastify";

process.env.MONGO_URI ??= "mongodb://placeholder/test";
process.env.JWT_SECRET ??= "test_jwt_secret_at_least_thirty_two_characters_long_xx";
process.env.KEY_ENCRYPTION_SECRET ??=
  "test_key_encryption_secret_at_least_thirty_two_chars_xx";
process.env.BODY_LIMIT_BYTES ??= "128";

let app: FastifyInstance;

beforeAll(async () => {
  vi.resetModules();
  const { buildApp } = await import("../src/app.js");
  app = await buildApp({ skipMongo: true });
});

afterAll(async () => {
  await app.close();
});

describe("request size handling", () => {
  it("returns a client-facing 413 instead of a 500 when the body is too large", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: {
        email: "test@example.com",
        password: "x".repeat(512),
      },
    });

    expect(res.statusCode).toBe(413);
    expect(
      res.json<{ error: { code: string; message: string } }>().error.message,
    ).toContain("Request body is too large");
  });
});

describe("rate limiting", () => {
  it("returns a 429 when the rate limit is exceeded", async () => {
    // We need to hit the limit of 200 requests.
    // app.inject is fast since it doesn't use the network.
    for (let i = 0; i < 200; i++) {
      await app.inject({
        method: "GET",
        url: "/health",
      });
    }

    const res = await app.inject({
      method: "GET",
      url: "/health",
    });

    expect(res.statusCode).toBe(429);
    const body = res.json<{ error: { code: string; message: string } }>();
    expect(body.error.code).toBe("RATE_LIMIT_EXCEEDED");
    expect(body.error.message).toContain("Rate limit exceeded");
  });
});
