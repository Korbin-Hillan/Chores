export type ErrorCode =
  | "UNAUTHORIZED"
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "VALIDATION_FAILED"
  | "RATE_LIMITED"
  | "OPENAI_KEY_MISSING"
  | "OPENAI_FAILED"
  | "PHOTO_REQUIRED"
  | "PHOTO_TOO_LARGE"
  | "INSUFFICIENT_POINTS"
  | "INTERNAL";

export class AppError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: ErrorCode,
    message: string,
    public readonly details?: Record<string, unknown>,
  ) {
    super(message);
    this.name = "AppError";
  }
}
