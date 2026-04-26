import OpenAI from "openai";
import type { ChoreDraft } from "../models/generationJob.js";
import { AppError } from "../utils/errors.js";

const TEXT_MODEL = "gpt-4o-mini";
const IMAGE_MODEL = "gpt-4o";

export function createOpenAIClient(apiKey: string): OpenAI {
  return new OpenAI({ apiKey });
}

export async function validateApiKey(apiKey: string): Promise<boolean> {
  const client = createOpenAIClient(apiKey);
  try {
    await client.chat.completions.create({
      model: TEXT_MODEL,
      messages: [{ role: "user", content: "Reply with OK." }],
      max_tokens: 5,
    });
    return true;
  } catch {
    return false;
  }
}

const CHORE_JSON_SCHEMA = {
  name: "chore_suggestions",
  schema: {
    type: "object",
    properties: {
      chores: {
        type: "array",
        items: {
          type: "object",
          properties: {
            title: { type: "string", maxLength: 80 },
            description: {
              anyOf: [
                { type: "string", maxLength: 300 },
                { type: "null" },
              ],
            },
            suggestedRoomName: { type: "string", maxLength: 40 },
            recurrence: {
              type: "object",
              properties: {
                kind: { type: "string", enum: ["none", "daily", "weekly", "monthly"] },
                weekdays: {
                  anyOf: [
                    { type: "array", items: { type: "integer", minimum: 0, maximum: 6 } },
                    { type: "null" },
                  ],
                },
                dayOfMonth: {
                  anyOf: [
                    { type: "integer", minimum: 1, maximum: 31 },
                    { type: "null" },
                  ],
                },
              },
              required: ["kind", "weekdays", "dayOfMonth"],
              additionalProperties: false,
            },
            estimatedMinutes: {
              anyOf: [
                { type: "integer", minimum: 1, maximum: 240 },
                { type: "null" },
              ],
            },
          },
          required: ["title", "description", "suggestedRoomName", "recurrence", "estimatedMinutes"],
          additionalProperties: false,
        },
      },
    },
    required: ["chores"],
    additionalProperties: false,
  },
  strict: true,
} as const;

type RawChoreDraft = {
  title: string;
  description: string | null;
  suggestedRoomName: string;
  recurrence: {
    kind: "none" | "daily" | "weekly" | "monthly";
    weekdays: number[] | null;
    dayOfMonth: number | null;
  };
  estimatedMinutes: number | null;
};

function buildSystemPrompt(existingRoomNames: string[]): string {
  const roomList = existingRoomNames.length > 0 ? existingRoomNames.join(", ") : "none yet";
  return `You are a helpful household chore assistant. Generate realistic, specific, and actionable chores for a home. Prefer concrete titles like "Wipe down stovetop" over vague ones like "Clean kitchen". Return 5 to 12 chores. Assign each chore to a room; prefer picking from these existing rooms when appropriate: ${roomList}. If a new room is needed, propose a short, clear room name. Choose recurrence based on the nature of the chore (daily for dishes, weekly for vacuuming, monthly for deep cleans, etc.).`;
}

function normalizeChoreDraft(raw: RawChoreDraft): ChoreDraft {
  const recurrence: ChoreDraft["recurrence"] = {
    kind: raw.recurrence.kind,
    ...(raw.recurrence.weekdays != null ? { weekdays: raw.recurrence.weekdays } : {}),
    ...(raw.recurrence.dayOfMonth != null ? { dayOfMonth: raw.recurrence.dayOfMonth } : {}),
  };

  return {
    title: raw.title,
    description: raw.description,
    suggestedRoomName: raw.suggestedRoomName,
    recurrence,
    estimatedMinutes: raw.estimatedMinutes,
  };
}

function toOpenAIAppError(operation: string, err: unknown): AppError {
  console.error(`[OpenAI] ${operation} failed`, err);

  if (err instanceof OpenAI.AuthenticationError) {
    return new AppError(502, "OPENAI_FAILED", "OpenAI rejected this API key.");
  }

  if (err instanceof OpenAI.RateLimitError) {
    return new AppError(
      502,
      "OPENAI_FAILED",
      "OpenAI rejected the request due to quota or rate limits on this API key.",
    );
  }

  if (err instanceof OpenAI.APIConnectionError) {
    return new AppError(502, "OPENAI_FAILED", "Couldn't reach OpenAI from the server.");
  }

  if (err instanceof OpenAI.APIError) {
    return new AppError(502, "OPENAI_FAILED", err.message, {
      status: err.status,
      code: err.code,
      type: err.type,
      requestId: err.request_id,
    });
  }

  if (err instanceof Error) {
    return new AppError(502, "OPENAI_FAILED", err.message);
  }

  return new AppError(502, "OPENAI_FAILED", "OpenAI request failed.");
}

export async function generateChoresFromText(
  apiKey: string,
  prompt: string,
  existingRoomNames: string[],
): Promise<{ chores: ChoreDraft[]; model: string; tokenUsage: { prompt: number; completion: number } }> {
  const client = createOpenAIClient(apiKey);
  const model = TEXT_MODEL;

  let response: OpenAI.Chat.Completions.ChatCompletion;
  try {
    response = await client.chat.completions.create({
      model,
      messages: [
        { role: "system", content: buildSystemPrompt(existingRoomNames) },
        { role: "user", content: prompt },
      ],
      response_format: { type: "json_schema", json_schema: CHORE_JSON_SCHEMA },
      max_tokens: 2000,
    });
  } catch (err) {
    throw toOpenAIAppError("Text generation", err);
  }

  const content = response.choices[0]?.message.content;
  if (!content) throw new AppError(502, "OPENAI_FAILED", "Empty response from OpenAI");

  let parsed: { chores: RawChoreDraft[] };
  try {
    parsed = JSON.parse(content) as { chores: RawChoreDraft[] };
  } catch (err) {
    console.error("[OpenAI] Text generation returned invalid JSON", { content, err });
    throw new AppError(502, "OPENAI_FAILED", "OpenAI returned malformed JSON.");
  }
  return {
    chores: parsed.chores.map(normalizeChoreDraft),
    model,
    tokenUsage: {
      prompt: response.usage?.prompt_tokens ?? 0,
      completion: response.usage?.completion_tokens ?? 0,
    },
  };
}

export async function generateChoresFromImage(
  apiKey: string,
  imageBase64: string,
  mimeType: "image/jpeg" | "image/png" | "image/webp",
  existingRoomNames: string[],
): Promise<{ chores: ChoreDraft[]; model: string; tokenUsage: { prompt: number; completion: number } }> {
  const client = createOpenAIClient(apiKey);
  const model = IMAGE_MODEL;

  let response: OpenAI.Chat.Completions.ChatCompletion;
  try {
    response = await client.chat.completions.create({
      model,
      messages: [
        { role: "system", content: buildSystemPrompt(existingRoomNames) },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: "Look at this room and suggest specific, actionable chores for it.",
            },
            {
              type: "image_url",
              image_url: { url: `data:${mimeType};base64,${imageBase64}`, detail: "low" },
            },
          ],
        },
      ],
      response_format: { type: "json_schema", json_schema: CHORE_JSON_SCHEMA },
      max_tokens: 2000,
    });
  } catch (err) {
    throw toOpenAIAppError("Image generation", err);
  }

  const content = response.choices[0]?.message.content;
  if (!content) throw new AppError(502, "OPENAI_FAILED", "Empty response from OpenAI");

  let parsed: { chores: RawChoreDraft[] };
  try {
    parsed = JSON.parse(content) as { chores: RawChoreDraft[] };
  } catch (err) {
    console.error("[OpenAI] Image generation returned invalid JSON", { content, err });
    throw new AppError(502, "OPENAI_FAILED", "OpenAI returned malformed JSON.");
  }
  return {
    chores: parsed.chores.map(normalizeChoreDraft),
    model,
    tokenUsage: {
      prompt: response.usage?.prompt_tokens ?? 0,
      completion: response.usage?.completion_tokens ?? 0,
    },
  };
}
