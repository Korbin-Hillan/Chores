import { Schema, model, type InferSchemaType, type HydratedDocument, type Types } from "mongoose";

const householdMemberSchema = new Schema(
  {
    householdId: { type: Schema.Types.ObjectId, ref: "Household", required: true, index: true },
    userId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    role: { type: String, enum: ["admin", "member"], required: true, default: "member" },
    currentStreak: { type: Number, required: true, default: 0 },
    longestStreak: { type: Number, required: true, default: 0 },
    lastCompletionAt: { type: Date, default: null },
  },
  { timestamps: true, versionKey: false },
);

householdMemberSchema.index({ householdId: 1, userId: 1 }, { unique: true });

export type HouseholdMemberDoc = HydratedDocument<InferSchemaType<typeof householdMemberSchema>>;

export type SafeMember = {
  id: string;
  householdId: string;
  userId: string;
  role: "admin" | "member";
  currentStreak: number;
  longestStreak: number;
  lastCompletionAt: string | null;
};

export function toSafeMember(doc: HouseholdMemberDoc): SafeMember {
  return {
    id: (doc._id as Types.ObjectId).toHexString(),
    householdId: (doc.householdId as Types.ObjectId).toHexString(),
    userId: (doc.userId as Types.ObjectId).toHexString(),
    role: doc.role as "admin" | "member",
    currentStreak: doc.currentStreak,
    longestStreak: doc.longestStreak,
    lastCompletionAt: doc.lastCompletionAt ? doc.lastCompletionAt.toISOString() : null,
  };
}

export const HouseholdMember = model<HouseholdMemberDoc>(
  "HouseholdMember",
  householdMemberSchema,
);
