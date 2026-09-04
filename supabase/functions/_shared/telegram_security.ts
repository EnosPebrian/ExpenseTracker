export const TELEGRAM_SOURCE_MAX_BYTES = 20 * 1024 * 1024;
export const TELEGRAM_CSV_MAX_BYTES = 10 * 1024 * 1024;
export const TELEGRAM_PAIRING_TTL_MS = 10 * 60 * 1000;

export class TelegramSafeError extends Error {
  constructor(
    readonly code: string,
    readonly safeMessage: string,
    readonly status = 422,
  ) {
    super(safeMessage);
  }
}

export function constantTimeEqual(expected: string, actual: string): boolean {
  const left = new TextEncoder().encode(expected);
  const right = new TextEncoder().encode(actual);
  let different = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index++) {
    different |= (left[index % Math.max(left.length, 1)] ?? 0) ^
      (right[index % Math.max(right.length, 1)] ?? 0);
  }
  return different === 0;
}

export function generatePairingToken(
  random: Uint8Array<ArrayBufferLike> = crypto.getRandomValues(
    new Uint8Array(24),
  ),
): string {
  if (random.length < 16) throw new Error("Pairing entropy is insufficient.");
  let binary = "";
  for (const byte of random) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll(
    "=",
    "",
  );
}

export async function sha256Hex(value: string | Uint8Array): Promise<string> {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : value;
  const stable = Uint8Array.from(bytes);
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", stable.buffer),
  );
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function safeJson(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type, x-telegram-bot-api-secret-token",
    },
  });
}
