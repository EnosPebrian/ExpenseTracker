import { createPairingMaterial, parseConnectionOperation } from "./_shared.ts";
import { TelegramSafeError } from "../_shared/telegram_security.ts";

function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}

Deno.test("pairing token has at least 128 bits and deterministic hash", async () => {
  const material = await createPairingMaterial(
    new Date("2026-08-31T00:00:00Z"),
    new Uint8Array(24).fill(7),
  );
  assert(material.token.length >= 22);
  assert(material.tokenHash.length === 64);
  assert(material.expiresAt.toISOString() === "2026-08-31T00:10:00.000Z");
  assert(!material.tokenHash.includes(material.token));
});

Deno.test("connection operations accept only UUID scoped input", () => {
  const book = "20000000-0000-4000-8000-000000000001";
  const member = "30000000-0000-4000-8000-000000000001";
  assert(
    parseConnectionOperation({ operation: "status", book_id: book })
      .operation === "status",
  );
  assert(
    parseConnectionOperation({
      operation: "generate",
      book_id: book,
      member_id: member,
    }).operation === "generate",
  );
  try {
    parseConnectionOperation({
      operation: "generate",
      book_id: "book",
      member_id: member,
    });
    throw new Error("Expected rejection");
  } catch (error) {
    assert(error instanceof TelegramSafeError);
  }
});
