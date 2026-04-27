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
    assignedToUserIdAtCompletion: { type: Schema.Types.ObjectId, ref: "User", default: null },
    reviewStatus: {
      type: String,
      enum: ["approved", "pending", "rejected"],
      required: true,
      default: "approved",
      index: true,
    },
    reviewedByUserId: { type: Schema.Types.ObjectId, ref: "User", default: null },
    reviewedAt: { type: Date, default: null },
    rejectionReason: { type: String, default: null },
    photo: { type: Buffer, default: null, select: false },
    photoContentType: { type: String, default: null },
    photoExpiresAt: { type: Date, default: null, index: true },
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
  assignedToUserIdAtCompletion: string | null;
  reviewStatus: "approved" | "pending" | "rejected";
  reviewedByUserId: string | null;
  reviewedAt: string | null;
  rejectionReason: string | null;
  hasPhoto: boolean;
};

export function toSafeCompletion(doc: CompletionDoc): SafeCompletion {
  return {
    id: (doc._id as Types.ObjectId).toHexString(),
    choreId: (doc.choreId as Types.ObjectId).toHexString(),
    householdId: (doc.householdId as Types.ObjectId).toHexString(),
    completedByUserId: (doc.completedByUserId as Types.ObjectId).toHexString(),
    completedAt: doc.completedAt.toISOString(),
    notes: doc.notes ?? null,
    assignedToUserIdAtCompletion: doc.assignedToUserIdAtCompletion
      ? (doc.assignedToUserIdAtCompletion as Types.ObjectId).toHexString()
      : null,
    reviewStatus: (doc.reviewStatus ?? "approved") as "approved" | "pending" | "rejected",
    reviewedByUserId: doc.reviewedByUserId
      ? (doc.reviewedByUserId as Types.ObjectId).toHexString()
      : null,
    reviewedAt: doc.reviewedAt ? doc.reviewedAt.toISOString() : null,
    rejectionReason: doc.rejectionReason ?? null,
    hasPhoto: Boolean(doc.photoContentType && doc.photoExpiresAt && doc.photoExpiresAt > new Date()),
  };
}

export const Completion = model<CompletionDoc>("Completion", completionSchema);
