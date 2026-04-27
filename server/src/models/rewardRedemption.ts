import { Schema, model, type InferSchemaType, type HydratedDocument, type Types } from "mongoose";

const rewardRedemptionSchema = new Schema(
  {
    householdId: { type: Schema.Types.ObjectId, ref: "Household", required: true, index: true },
    rewardId: { type: Schema.Types.ObjectId, ref: "Reward", required: true, index: true },
    requestedByUserId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    costPointsSnapshot: { type: Number, required: true },
    rewardTitleSnapshot: { type: String, required: true },
    status: {
      type: String,
      enum: ["pending", "approved", "rejected"],
      required: true,
      default: "pending",
      index: true,
    },
    reviewedByUserId: { type: Schema.Types.ObjectId, ref: "User", default: null },
    reviewedAt: { type: Date, default: null },
    rejectionReason: { type: String, default: null },
  },
  { timestamps: true, versionKey: false },
);

export type RewardRedemptionDoc = HydratedDocument<
  InferSchemaType<typeof rewardRedemptionSchema>
>;

export type SafeRewardRedemption = {
  id: string;
  householdId: string;
  rewardId: string;
  requestedByUserId: string;
  costPointsSnapshot: number;
  rewardTitleSnapshot: string;
  status: "pending" | "approved" | "rejected";
  reviewedByUserId: string | null;
  reviewedAt: string | null;
  rejectionReason: string | null;
  createdAt: string;
};

export function toSafeRewardRedemption(doc: RewardRedemptionDoc): SafeRewardRedemption {
  return {
    id: (doc._id as Types.ObjectId).toHexString(),
    householdId: (doc.householdId as Types.ObjectId).toHexString(),
    rewardId: (doc.rewardId as Types.ObjectId).toHexString(),
    requestedByUserId: (doc.requestedByUserId as Types.ObjectId).toHexString(),
    costPointsSnapshot: doc.costPointsSnapshot,
    rewardTitleSnapshot: doc.rewardTitleSnapshot,
    status: doc.status as "pending" | "approved" | "rejected",
    reviewedByUserId: doc.reviewedByUserId
      ? (doc.reviewedByUserId as Types.ObjectId).toHexString()
      : null,
    reviewedAt: doc.reviewedAt ? doc.reviewedAt.toISOString() : null,
    rejectionReason: doc.rejectionReason ?? null,
    createdAt: (doc as unknown as { createdAt: Date }).createdAt.toISOString(),
  };
}

export const RewardRedemption = model<RewardRedemptionDoc>(
  "RewardRedemption",
  rewardRedemptionSchema,
);
