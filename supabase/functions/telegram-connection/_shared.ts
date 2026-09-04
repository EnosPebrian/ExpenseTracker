import {
  generatePairingToken,
  sha256Hex,
  TELEGRAM_PAIRING_TTL_MS,
  TelegramSafeError,
} from "../_shared/telegram_security.ts";

export type ConnectionOperation =
  | { operation: "status"; bookId: string }
  | { operation: "generate"; bookId: string; memberId: string }
  | { operation: "disconnect"; bookId: string };

export function parseConnectionOperation(value: unknown): ConnectionOperation {
  if (!isObject(value)) {
    throw new TelegramSafeError("invalid_request", "Invalid request.");
  }
  const operation = value.operation;
  const bookId = uuid(value.book_id);
  if (operation === "status") return { operation, bookId };
  if (operation === "disconnect") return { operation, bookId };
  if (operation === "generate") {
    return { operation, bookId, memberId: uuid(value.member_id) };
  }
  throw new TelegramSafeError("invalid_request", "Invalid request.");
}

export async function createPairingMaterial(
  now = new Date(),
  random?: Uint8Array,
): Promise<{ token: string; tokenHash: string; expiresAt: Date }> {
  const token = generatePairingToken(random);
  return {
    token,
    tokenHash: await sha256Hex(token),
    expiresAt: new Date(now.getTime() + TELEGRAM_PAIRING_TTL_MS),
  };
}

function uuid(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
  ) {
    throw new TelegramSafeError("invalid_request", "Invalid request.");
  }
  return value;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
