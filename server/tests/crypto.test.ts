import { describe, expect, it } from "vitest";

process.env.MONGO_URI ??= "mongodb://placeholder/test";
process.env.JWT_SECRET ??= "test_jwt_secret_at_least_thirty_two_characters_long_xx";
process.env.KEY_ENCRYPTION_SECRET ??=
  "test_key_encryption_secret_at_least_thirty_two_chars_xx";

const { encrypt, decrypt } = await import("../src/services/crypto.js");

describe("crypto", () => {
  it("round-trips a plaintext", () => {
    const original = "sk-fake-openai-key-for-test-only-12345";
    const payload = encrypt(original);
    expect(payload.ciphertext).not.toContain(original);
    expect(decrypt(payload)).toBe(original);
  });

  it("produces a different IV every time", () => {
    const a = encrypt("same plaintext");
    const b = encrypt("same plaintext");
    expect(a.iv).not.toBe(b.iv);
    expect(a.ciphertext).not.toBe(b.ciphertext);
  });

  it("rejects tampered ciphertext", () => {
    const payload = encrypt("hello");
    const tampered = { ...payload, ciphertext: Buffer.from("tampered").toString("base64") };
    expect(() => decrypt(tampered)).toThrow();
  });
});
