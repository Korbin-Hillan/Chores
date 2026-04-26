import "dotenv/config";
import { z } from "zod";

const schema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(8080),
  HOST: z.string().default("0.0.0.0"),
  BODY_LIMIT_BYTES: z.coerce.number().int().positive().default(8 * 1024 * 1024),
  MONGO_URI: z.string().min(1),
  JWT_SECRET: z.string().min(32, "JWT_SECRET must be at least 32 characters"),
  KEY_ENCRYPTION_SECRET: z
    .string()
    .min(32, "KEY_ENCRYPTION_SECRET must be at least 32 characters"),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace"]).default("info"),
});

const parsed = schema.safeParse(process.env);
if (!parsed.success) {
  // Logger isn't built yet — process.stderr is the only safe channel here.
  process.stderr.write(`Invalid environment configuration:\n${parsed.error.toString()}\n`);
  process.exit(1);
}

export const env = parsed.data;
export type Env = z.infer<typeof schema>;
