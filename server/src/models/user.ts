import { Schema, model, type InferSchemaType, type HydratedDocument, type Types } from "mongoose";

const userSchema = new Schema(
  {
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    passwordHash: { type: String, required: true },
    displayName: { type: String, required: true, trim: true },
    currentHouseholdId: { type: Schema.Types.ObjectId, ref: "Household", default: null },
  },
  { timestamps: true, versionKey: false },
);

export type UserDoc = HydratedDocument<InferSchemaType<typeof userSchema>>;

export type SafeUser = {
  id: string;
  email: string;
  displayName: string;
  currentHouseholdId: string | null;
};

export function toSafeUser(doc: UserDoc): SafeUser {
  return {
    id: (doc._id as Types.ObjectId).toHexString(),
    email: doc.email,
    displayName: doc.displayName,
    currentHouseholdId: doc.currentHouseholdId
      ? (doc.currentHouseholdId as Types.ObjectId).toHexString()
      : null,
  };
}

export const User = model<UserDoc>("User", userSchema);
