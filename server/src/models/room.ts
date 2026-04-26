import { Schema, model, type InferSchemaType, type HydratedDocument, type Types } from "mongoose";

const roomSchema = new Schema(
  {
    householdId: { type: Schema.Types.ObjectId, ref: "Household", required: true, index: true },
    name: { type: String, required: true, trim: true },
    icon: { type: String, default: null },
    archived: { type: Boolean, required: true, default: false },
  },
  { timestamps: true, versionKey: false },
);

export type RoomDoc = HydratedDocument<InferSchemaType<typeof roomSchema>>;

export type SafeRoom = {
  id: string;
  householdId: string;
  name: string;
  icon: string | null;
  archived: boolean;
};

export function toSafeRoom(doc: RoomDoc): SafeRoom {
  return {
    id: (doc._id as Types.ObjectId).toHexString(),
    householdId: (doc.householdId as Types.ObjectId).toHexString(),
    name: doc.name,
    icon: doc.icon ?? null,
    archived: doc.archived,
  };
}

export const Room = model<RoomDoc>("Room", roomSchema);
