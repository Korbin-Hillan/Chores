import { Schema, model, type InferSchemaType, type HydratedDocument, type Types } from "mongoose";

const completionSchema = new Schema(
  {
    choreId: { type: Schema.Types.ObjectId, ref: "Chore", required: true, index: true },
    householdId: { type: Schema.Types.ObjectId, ref: "Household", required: true, index: true },
    completedByUserId: {
      type: Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    completedAt: { type: Date, required: true, default: () => new Date(), index: true },
    notes: { type: String, default: null },
  },
  { versionKey: false },
);

export type CompletionDoc = HydratedDocument<InferSchemaType<typeof completionSchema>>;

export type SafeCompletion = {
  id: string;
  choreId: string;
  householdId: string;
  completedByUserId: string;
  completedAt: string;
  notes: string | null;
};

export function toSafeCompletion(doc: CompletionDoc): SafeCompletion {
  return {
    id: (doc._id as Types.ObjectId).toHexString(),
    choreId: (doc.choreId as Types.ObjectId).toHexString(),
    householdId: (doc.householdId as Types.ObjectId).toHexString(),
    completedByUserId: (doc.completedByUserId as Types.ObjectId).toHexString(),
    completedAt: doc.completedAt.toISOString(),
    notes: doc.notes ?? null,
  };
}

export const Completion = model<CompletionDoc>("Completion", completionSchema);
