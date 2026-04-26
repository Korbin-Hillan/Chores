import { Schema, model, type InferSchemaType, type HydratedDocument, type Types } from "mongoose";

const recurrenceSchema = new Schema(
  {
    kind: {
      type: String,
      enum: ["none", "daily", "weekly", "monthly"],
      required: true,
      default: "none",
    },
    weekdays: { type: [Number], default: undefined },
    dayOfMonth: { type: Number, default: undefined },
  },
  { _id: false },
);

const choreSchema = new Schema(
  {
    householdId: { type: Schema.Types.ObjectId, ref: "Household", required: true, index: true },
    roomId: { type: Schema.Types.ObjectId, ref: "Room", required: true, index: true },
    title: { type: String, required: true, trim: true },
    description: { type: String, default: null },
    recurrence: { type: recurrenceSchema, required: true, default: () => ({ kind: "none" }) },
    estimatedMinutes: { type: Number, default: null },
    points: { type: Number, required: true, default: 1 },
    createdByUserId: { type: Schema.Types.ObjectId, ref: "User", required: true },
    source: {
      type: String,
      enum: ["manual", "ai_text", "ai_image"],
      required: true,
      default: "manual",
    },
    archived: { type: Boolean, required: true, default: false },
  },
  { timestamps: true, versionKey: false },
);

export type ChoreDoc = HydratedDocument<InferSchemaType<typeof choreSchema>>;

export type SafeChore = {
  id: string;
  householdId: string;
  roomId: string;
  title: string;
  description: string | null;
  recurrence: { kind: string; weekdays?: number[]; dayOfMonth?: number };
  estimatedMinutes: number | null;
  points: number;
  createdByUserId: string;
  source: string;
  archived: boolean;
  createdAt: string;
};

export function toSafeChore(doc: ChoreDoc): SafeChore {
  return {
    id: (doc._id as Types.ObjectId).toHexString(),
    householdId: (doc.householdId as Types.ObjectId).toHexString(),
    roomId: (doc.roomId as Types.ObjectId).toHexString(),
    title: doc.title,
    description: doc.description ?? null,
    recurrence: doc.recurrence as SafeChore["recurrence"],
    estimatedMinutes: doc.estimatedMinutes ?? null,
    points: doc.points,
    createdByUserId: (doc.createdByUserId as Types.ObjectId).toHexString(),
    source: doc.source,
    archived: doc.archived,
    createdAt: (doc as unknown as { createdAt: Date }).createdAt.toISOString(),
  };
}

export const Chore = model<ChoreDoc>("Chore", choreSchema);
