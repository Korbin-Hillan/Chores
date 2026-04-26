import { Schema, model, type InferSchemaType, type HydratedDocument, type Types } from "mongoose";

const encryptedKeySchema = new Schema(
  {
    ciphertext: { type: String, required: true },
    iv: { type: String, required: true },
    tag: { type: String, required: true },
  },
  { _id: false },
);

const householdSchema = new Schema(
  {
    name: { type: String, required: true, trim: true },
    inviteCode: { type: String, required: true, unique: true, uppercase: true },
    adminUserId: { type: Schema.Types.ObjectId, ref: "User", required: true },
    openAIKey: { type: encryptedKeySchema, default: null },
    openAIKeySetAt: { type: Date, default: null },
  },
  { timestamps: true, versionKey: false },
);

export type HouseholdDoc = HydratedDocument<InferSchemaType<typeof householdSchema>>;

export type SafeHousehold = {
  id: string;
  name: string;
  inviteCode: string;
  adminUserId: string;
  openAIKeyIsSet: boolean;
  openAIKeySetAt: string | null;
};

export function toSafeHousehold(doc: HouseholdDoc): SafeHousehold {
  return {
    id: (doc._id as Types.ObjectId).toHexString(),
    name: doc.name,
    inviteCode: doc.inviteCode,
    adminUserId: (doc.adminUserId as Types.ObjectId).toHexString(),
    openAIKeyIsSet: doc.openAIKey != null,
    openAIKeySetAt: doc.openAIKeySetAt ? doc.openAIKeySetAt.toISOString() : null,
  };
}

export const Household = model<HouseholdDoc>("Household", householdSchema);
