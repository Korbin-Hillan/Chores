import { Schema, model, type InferSchemaType, type HydratedDocument, type Types } from "mongoose";

const rewardSchema = new Schema(
  {
    householdId: { type: Schema.Types.ObjectId, ref: "Household", required: true, index: true },
    title: { type: String, required: true, trim: true },
    description: { type: String, default: null },
    costPoints: { type: Number, required: true, min: 1 },
    archived: { type: Boolean, required: true, default: false },
    createdByUserId: { type: Schema.Types.ObjectId, ref: "User", required: true },
  },
  { timestamps: true, versionKey: false },
);

export type RewardDoc = HydratedDocument<InferSchemaType<typeof rewardSchema>>;

export type SafeReward = {
  id: string;
  householdId: string;
  title: string;
  description: string | null;
  costPoints: number;
  archived: boolean;
  createdByUserId: string;
  createdAt: string;
};

export function toSafeReward(doc: RewardDoc): SafeReward {
  return {
    id: (doc._id as Types.ObjectId).toHexString(),
    householdId: (doc.householdId as Types.ObjectId).toHexString(),
    title: doc.title,
    description: doc.description ?? null,
    costPoints: doc.costPoints,
    archived: doc.archived,
    createdByUserId: (doc.createdByUserId as Types.ObjectId).toHexString(),
    createdAt: (doc as unknown as { createdAt: Date }).createdAt.toISOString(),
  };
}

export const Reward = model<RewardDoc>("Reward", rewardSchema);
