import { Schema, model, type InferSchemaType, type HydratedDocument, type Types } from "mongoose";

const choreDraftSchema = new Schema(
  {
    title: { type: String, required: true },
    description: { type: String, default: null },
    suggestedRoomName: { type: String, required: true },
    recurrence: {
      type: {
        kind: { type: String, enum: ["none", "daily", "weekly", "monthly"], required: true },
        weekdays: { type: [Number], default: undefined },
        dayOfMonth: { type: Number, default: undefined },
      },
      required: true,
      _id: false,
    },
    estimatedMinutes: { type: Number, default: null },
  },
  { _id: false },
);

const generationJobSchema = new Schema(
  {
    householdId: { type: Schema.Types.ObjectId, ref: "Household", required: true, index: true },
    requestedByUserId: { type: Schema.Types.ObjectId, ref: "User", required: true },
    inputType: { type: String, enum: ["text", "image"], required: true },
    inputSummary: { type: String, required: true, maxlength: 200 },
    model: { type: String, required: true },
    tokenUsage: {
      type: { prompt: Number, completion: Number },
      default: { prompt: 0, completion: 0 },
      _id: false,
    },
    suggestedChores: { type: [choreDraftSchema], default: [] },
    createdChoreIds: { type: [Schema.Types.ObjectId], default: [] },
  },
  { timestamps: true, versionKey: false },
);

export type GenerationJobDoc = HydratedDocument<InferSchemaType<typeof generationJobSchema>>;

export type ChoreDraft = {
  title: string;
  description?: string | null;
  suggestedRoomName: string;
  recurrence: { kind: "none" | "daily" | "weekly" | "monthly"; weekdays?: number[]; dayOfMonth?: number };
  estimatedMinutes?: number | null;
};

export const GenerationJob = model<GenerationJobDoc>("GenerationJob", generationJobSchema);
