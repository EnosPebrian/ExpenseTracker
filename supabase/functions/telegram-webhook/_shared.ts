import {
  constantTimeEqual,
  sha256Hex,
  TELEGRAM_CSV_MAX_BYTES,
  TELEGRAM_SOURCE_MAX_BYTES,
  TelegramSafeError,
} from "../_shared/telegram_security.ts";

export type TelegramFile = {
  fileId: string;
  size: number | null;
  name: string;
  mimeType: string;
  route: "csv" | "receipt" | "statement";
};

export type TelegramClaim = {
  claimed: boolean;
  reason?: string;
  connection_id?: string;
  currency_code?: string;
};

export type TelegramGateway = {
  claim(input: {
    updateId: number;
    userId: number;
    chatId: number;
    messageId: number;
    eventType: "command" | "link" | "attachment" | "unsupported";
  }): Promise<TelegramClaim>;
  consumeToken(input: {
    updateId: number;
    tokenHash: string;
    userId: number;
    chatId: number;
  }): Promise<boolean>;
  revoke(input: {
    updateId: number;
    userId: number;
    chatId: number;
  }): Promise<boolean>;
  finish(
    updateId: number,
    status: "completed" | "failed" | "ignored",
    code?: string,
  ): Promise<void>;
  createInbox(input: {
    updateId: number;
    connectionId: string;
    session: Record<string, unknown>;
    drafts: Record<string, unknown>[];
  }): Promise<string>;
  getFile(fileId: string): Promise<{ path: string; size: number | null }>;
  download(path: string): Promise<Uint8Array>;
  extract(
    kind: "receipt_invoice" | "bank_statement",
    file: { name: string; mimeType: string; bytes: Uint8Array },
  ): Promise<Record<string, unknown>>;
  send(chatId: number, text: string): Promise<void>;
  schedule?(work: Promise<void>): void;
};

type PrivateMessage = {
  updateId: number;
  userId: number;
  chatId: number;
  messageId: number;
  text: string;
  caption: string;
  file: TelegramFile | null;
};

type NormalizedRow = {
  key: string;
  index: number;
  date: string;
  description: string;
  amountMinor: number;
  type: "expense" | "income";
  category: string;
  reference: string;
  note: string;
  merchantHint: string;
  rawAmount: string;
};

const replies = {
  help:
    "Send a receipt photo, an unlocked statement PDF, or a canonical Pilgrim CSV. Files are added to Import Inbox for review.",
  linked: "Telegram is connected to Pilgrim Tracker.",
  linkFailed:
    "That pairing command is invalid or expired. Generate a new one in Pilgrim Tracker.",
  unlinked: "Telegram is disconnected from Pilgrim Tracker.",
  notLinked: "Connect Telegram from Pilgrim Tracker Integrations first.",
  received: (count: number) =>
    count === 1
      ? "Received. Added to Pilgrim Tracker Import Inbox for review."
      : `Received. Added ${count} transaction drafts to Pilgrim Tracker Import Inbox for review.`,
  unsupported:
    "Unsupported source. Send a receipt image, unlocked statement PDF, or canonical Pilgrim CSV.",
  nonCanonical: "This CSV needs column mapping. Import it in Pilgrim Tracker.",
  tooLarge: "This file is too large to import through Telegram.",
  failed:
    "This source could not be processed safely. Import it in Pilgrim Tracker.",
  rate: "Too many recent requests. Please try again later.",
};

export async function handleTelegramWebhook(
  request: Request,
  gateway: TelegramGateway,
  webhookSecret: string,
): Promise<Response> {
  if (request.method !== "POST") return response(405);
  const supplied = request.headers.get("x-telegram-bot-api-secret-token") ?? "";
  if (!webhookSecret || !constantTimeEqual(webhookSecret, supplied)) {
    return response(401);
  }
  let value: unknown;
  try {
    value = await request.json();
  } catch {
    return response(400);
  }
  const message = parsePrivateMessage(value);
  if (!message) return response(200);
  const eventType = classifyEvent(message);
  let claim: TelegramClaim;
  try {
    claim = await gateway.claim({
      updateId: message.updateId,
      userId: message.userId,
      chatId: message.chatId,
      messageId: message.messageId,
      eventType,
    });
  } catch {
    return response(503);
  }
  if (!claim.claimed) {
    if (claim.reason === "duplicate") return response(200);
    await safeReply(
      gateway,
      message.chatId,
      claim.reason === "rate_limited" ? replies.rate : replies.notLinked,
    );
    return response(200);
  }
  const work = processClaimed(message, eventType, claim, gateway);
  if (gateway.schedule) gateway.schedule(work);
  else await work;
  return response(200);
}

async function processClaimed(
  message: PrivateMessage,
  eventType: "command" | "link" | "attachment" | "unsupported",
  claim: TelegramClaim,
  gateway: TelegramGateway,
): Promise<void> {
  try {
    if (eventType === "link") {
      const token = message.text.trim().split(/\s+/)[1] ?? "";
      const linked = token.length >= 20 && await gateway.consumeToken({
        updateId: message.updateId,
        tokenHash: await sha256Hex(token),
        userId: message.userId,
        chatId: message.chatId,
      });
      await gateway.send(
        message.chatId,
        linked ? replies.linked : replies.linkFailed,
      );
      if (!linked) {
        await gateway.finish(
          message.updateId,
          "failed",
          "invalid_pairing_token",
        );
      }
      return;
    }
    if (message.text === "/unlink") {
      await gateway.revoke({
        updateId: message.updateId,
        userId: message.userId,
        chatId: message.chatId,
      });
      await gateway.send(message.chatId, replies.unlinked);
      return;
    }
    if (message.text === "/start" || message.text === "/help") {
      await gateway.finish(message.updateId, "completed");
      await gateway.send(message.chatId, replies.help);
      return;
    }
    if (message.text === "/receipt" || message.text === "/statement") {
      await gateway.finish(message.updateId, "completed");
      await gateway.send(
        message.chatId,
        `Attach one supported file and use ${message.text} as its caption.`,
      );
      return;
    }
    if (eventType !== "attachment" || !message.file || !claim.connection_id) {
      await gateway.finish(message.updateId, "ignored", "unsupported_source");
      await gateway.send(message.chatId, replies.unsupported);
      return;
    }
    await ingestAttachment(message, claim, gateway);
  } catch (error) {
    const safe = error instanceof TelegramSafeError ? error : null;
    try {
      await gateway.finish(
        message.updateId,
        "failed",
        safe?.code ?? "processing_failed",
      );
    } catch { /* original safe failure is authoritative */ }
    await safeReply(
      gateway,
      message.chatId,
      safe?.code === "noncanonical_csv"
        ? replies.nonCanonical
        : safe?.code === "file_too_large"
        ? replies.tooLarge
        : replies.failed,
    );
  }
}

async function ingestAttachment(
  message: PrivateMessage,
  claim: TelegramClaim,
  gateway: TelegramGateway,
): Promise<void> {
  const file = message.file!;
  const limit = file.route === "csv"
    ? TELEGRAM_CSV_MAX_BYTES
    : TELEGRAM_SOURCE_MAX_BYTES;
  if (file.size != null && file.size > limit) throw safe("file_too_large");
  const remote = await gateway.getFile(file.fileId);
  if (!safeTelegramPath(remote.path)) throw safe("unsafe_file_path");
  if (remote.size != null && remote.size > limit) throw safe("file_too_large");
  let bytes: Uint8Array | null = await gateway.download(remote.path);
  try {
    if (bytes.length === 0) throw safe("empty_file");
    if (bytes.length > limit) throw safe("file_too_large");
    validateMagic(bytes, file.mimeType, file.route);
    const fingerprint = await sha256Hex(bytes);
    const currency = /^[A-Z]{3}$/.test(claim.currency_code ?? "")
      ? claim.currency_code!
      : "IDR";
    const rows = file.route === "csv"
      ? await parseCanonicalCsv(bytes, currency)
      : normalizeExtraction(
        await gateway.extract(
          file.route === "receipt" ? "receipt_invoice" : "bank_statement",
          { name: file.name, mimeType: file.mimeType, bytes },
        ),
        file.route,
        currency,
      );
    const sessionId = crypto.randomUUID();
    const sourceType = file.route === "csv"
      ? "csv"
      : file.route === "receipt"
      ? "receipt"
      : "bankStatement";
    const drafts = await Promise.all(rows.map(async (row) => {
      const rawIdentity = JSON.stringify({
        row: file.route === "csv" ? Number(row.key) : row.key,
        date: row.date,
        description: row.description,
        amount: row.rawAmount,
        debit: "",
        credit: "",
        reference: row.reference,
      });
      return {
        id: crypto.randomUUID(),
        source_row_identity: await sha256Hex(rawIdentity),
        source_row_key: row.key,
        source_index: row.index,
        transaction_date: `${row.date}T00:00:00.000Z`,
        description: row.description,
        amount_minor: row.amountMinor,
        currency_code: currency,
        transaction_type: row.type,
        category_name: row.category,
        category_provenance: row.category ? "source" : "unresolved",
        reference_text: row.reference,
        note_text: row.note,
        merchant_hint: row.merchantHint,
        warnings: [],
      };
    }));
    await gateway.createInbox({
      updateId: message.updateId,
      connectionId: claim.connection_id!,
      session: {
        id: sessionId,
        source_type: sourceType,
        title: safeTitle(file, sourceType),
        source_fingerprint: fingerprint,
        summary: { origin: "telegram", draft_count: drafts.length },
      },
      drafts,
    });
    await gateway.send(message.chatId, replies.received(drafts.length));
  } finally {
    bytes = null;
  }
}

export async function parseCanonicalCsv(
  bytes: Uint8Array,
  currency: string,
): Promise<NormalizedRow[]> {
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw safe("invalid_csv");
  }
  if (text.startsWith("\uFEFF")) text = text.slice(1);
  const table = parseCsv(text);
  if (table.length < 2) throw safe("invalid_csv");
  if (table.length - 1 > 5000) throw safe("invalid_csv");
  const headers = table[0].map((item) => item.trim().toLowerCase());
  const required = ["date", "description", "amount", "type"];
  if (
    !required.every((name) =>
      headers.filter((item) => item === name).length === 1
    )
  ) {
    throw safe("noncanonical_csv");
  }
  if (
    headers.some((name) =>
      ![...required, "category", "reference", "note"].includes(name)
    )
  ) {
    throw safe("noncanonical_csv");
  }
  const at = (row: string[], name: string) => {
    const index = headers.indexOf(name);
    return index < 0 ? "" : (row[index] ?? "");
  };
  return table.slice(1).filter((row) => row.some((field) => field.trim())).map(
    (row, offset) => {
      const date = canonicalDate(at(row, "date"));
      const description = at(row, "description").trim();
      const rawAmount = at(row, "amount").trim();
      const type = at(row, "type").trim().toLowerCase();
      if (
        !description || description.length > 10000 ||
        !["expense", "income"].includes(type)
      ) {
        throw safe("invalid_csv");
      }
      return {
        key: String(offset + 2),
        index: offset + 2,
        date,
        description,
        amountMinor: parseMoney(rawAmount, currency),
        type: type as "expense" | "income",
        category: bounded(at(row, "category")),
        reference: bounded(at(row, "reference")),
        note: bounded(at(row, "note")),
        merchantHint: "",
        rawAmount,
      };
    },
  );
}

function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (quoted) {
      if (char === '"' && text[i + 1] === '"') {
        field += '"';
        i++;
      } else if (char === '"') quoted = false;
      else field += char;
      continue;
    }
    if (char === '"' && field.length === 0) quoted = true;
    else if (char === ",") {
      row.push(field);
      field = "";
    } else if (char === "\n") {
      row.push(field.replace(/\r$/, ""));
      rows.push(row);
      row = [];
      field = "";
    } else field += char;
    if (field.length > 10000 || row.length > 100) throw safe("invalid_csv");
  }
  if (quoted) throw safe("invalid_csv");
  row.push(field.replace(/\r$/, ""));
  if (row.some((item) => item.length)) rows.push(row);
  return rows;
}

function normalizeExtraction(
  envelope: Record<string, unknown>,
  route: "receipt" | "statement",
  currency: string,
): NormalizedRow[] {
  const result = object(envelope.result);
  if (route === "receipt") {
    const rawAmount = string(result.total);
    const merchant = nullable(result.merchant_name)?.trim() ?? "";
    return [{
      key: "receipt",
      index: 1,
      date: canonicalDate(nullable(result.transaction_date) ?? ""),
      description: merchant || "Receipt expense",
      amountMinor: parseMoney(rawAmount, currency),
      type: "expense",
      category: "",
      reference: nullable(result.receipt_number) ?? "",
      note: result.document_type === "invoice"
        ? "Confirm this invoice was paid before saving."
        : "",
      merchantHint: merchant,
      rawAmount,
    }];
  }
  const transactions = Array.isArray(result.transactions)
    ? result.transactions
    : [];
  if (transactions.length === 0 || transactions.length > 5000) {
    throw safe("extraction_failed");
  }
  const occurrences = new Map<string, number>();
  return transactions.map((value, offset) => {
    const row = object(value);
    const date = canonicalDate(
      nullable(row.transaction_date) ?? nullable(row.posting_date) ?? "",
    );
    const description = string(row.description).trim().replace(/\s+/g, " ");
    const rawAmount = string(row.amount).trim();
    const direction = string(row.direction);
    const reference = nullable(row.reference)?.trim() ?? "";
    if (!description || !["debit", "credit"].includes(direction)) {
      throw safe("extraction_failed");
    }
    const canonical = [
      date,
      description.toLowerCase(),
      rawAmount,
      direction,
      reference,
    ].join("|");
    const occurrence = occurrences.get(canonical) ?? 0;
    occurrences.set(canonical, occurrence + 1);
    return {
      key: `${canonical}#${occurrence}`,
      index: offset + 1,
      date,
      description,
      amountMinor: parseMoney(rawAmount, currency),
      type: direction === "debit" ? "expense" : "income",
      category: "",
      reference,
      note: row.transaction_date == null && row.posting_date != null
        ? "Posting date used; transaction date was unavailable."
        : "",
      merchantHint: "",
      rawAmount,
    };
  });
}

function parsePrivateMessage(value: unknown): PrivateMessage | null {
  if (!isObject(value) || !Number.isSafeInteger(value.update_id)) return null;
  const raw = isObject(value.message) ? value.message : null;
  if (
    !raw || !isObject(raw.chat) || raw.chat.type !== "private" ||
    !isObject(raw.from) || raw.from.is_bot === true ||
    !Number.isSafeInteger(raw.from.id) || !Number.isSafeInteger(raw.chat.id) ||
    raw.from.id !== raw.chat.id || !Number.isSafeInteger(raw.message_id)
  ) return null;
  const text = typeof raw.text === "string" ? raw.text.trim() : "";
  const caption = typeof raw.caption === "string" ? raw.caption.trim() : "";
  return {
    updateId: value.update_id as number,
    userId: raw.from.id as number,
    chatId: raw.chat.id as number,
    messageId: raw.message_id as number,
    text,
    caption,
    file: attachment(raw, caption),
  };
}

function attachment(
  raw: Record<string, unknown>,
  caption: string,
): TelegramFile | null {
  const statement = caption === "/statement";
  if (Array.isArray(raw.photo) && raw.photo.length) {
    const photo = raw.photo.filter(isObject).at(-1);
    if (!photo || typeof photo.file_id !== "string") return null;
    return {
      fileId: photo.file_id,
      size: numberOrNull(photo.file_size),
      name: "telegram-photo.jpg",
      mimeType: "image/jpeg",
      route: statement ? "statement" : "receipt",
    };
  }
  if (!isObject(raw.document) || typeof raw.document.file_id !== "string") {
    return null;
  }
  const mime = typeof raw.document.mime_type === "string"
    ? raw.document.mime_type
    : "";
  const name = typeof raw.document.file_name === "string"
    ? raw.document.file_name.slice(0, 255)
    : "document";
  const route = mime === "text/csv" || name.toLowerCase().endsWith(".csv")
    ? "csv"
    : mime === "application/pdf"
    ? "statement"
    : ["image/jpeg", "image/png", "image/webp"].includes(mime)
    ? (statement ? "statement" : "receipt")
    : null;
  return route
    ? {
      fileId: raw.document.file_id,
      size: numberOrNull(raw.document.file_size),
      name,
      mimeType: mime ||
        (route === "csv" ? "text/csv" : "application/octet-stream"),
      route,
    }
    : null;
}

function classifyEvent(
  message: PrivateMessage,
): "command" | "link" | "attachment" | "unsupported" {
  if (message.text.startsWith("/link ")) return "link";
  if (message.text.startsWith("/")) return "command";
  return message.file ? "attachment" : "unsupported";
}

function validateMagic(bytes: Uint8Array, mime: string, route: string): void {
  const head = new TextDecoder().decode(bytes.slice(0, 12));
  if (head.startsWith("PK\x03\x04")) throw safe("unsupported_source");
  if (route === "csv") return;
  const valid = mime === "application/pdf"
    ? head.startsWith("%PDF-")
    : mime === "image/jpeg"
    ? bytes[0] === 0xff && bytes[1] === 0xd8
    : mime === "image/png"
    ? bytes[0] === 0x89 && head.slice(1, 4) === "PNG"
    : mime === "image/webp"
    ? head.startsWith("RIFF") && head.slice(8, 12) === "WEBP"
    : false;
  if (!valid) throw safe("unsupported_source");
  if (
    mime === "application/pdf" &&
    new TextDecoder().decode(bytes).includes("/Encrypt")
  ) {
    throw safe("protected_pdf");
  }
}

function safeTelegramPath(path: string): boolean {
  return path.length > 0 && path.length <= 512 && !path.includes("..") &&
    !path.includes(":") && !path.startsWith("/") &&
    /^[a-zA-Z0-9_./-]+$/.test(path);
}

function parseMoney(value: string, currency: string): number {
  const decimals = ["IDR", "JPY", "KRW", "VND"].includes(currency) ? 0 : 2;
  if (!/^\d+(?:\.\d+)?$/.test(value.trim())) throw safe("invalid_amount");
  const [whole, fraction = ""] = value.trim().split(".");
  if (fraction.length > decimals || (decimals === 0 && fraction.length)) {
    throw safe("invalid_amount");
  }
  const minor = Number(whole) * 10 ** decimals +
    Number(fraction.padEnd(decimals, "0") || 0);
  if (!Number.isSafeInteger(minor) || minor <= 0) throw safe("invalid_amount");
  return minor;
}

function canonicalDate(value: string): string {
  const date = value.trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw safe("invalid_date");
  const parsed = new Date(`${date}T00:00:00.000Z`);
  if (
    Number.isNaN(parsed.valueOf()) || parsed.toISOString().slice(0, 10) !== date
  ) throw safe("invalid_date");
  return date;
}

function safeTitle(file: TelegramFile, type: string): string {
  if (type === "csv") {
    const clean = file.name.replace(/[^a-zA-Z0-9._ -]/g, "_").slice(0, 100);
    return `CSV — ${clean || "transactions.csv"}`;
  }
  const day = new Date().toISOString().slice(0, 10);
  return type === "receipt"
    ? `Receipt — ${day}`
    : `Bank statement — ${day.slice(0, 7)}`;
}

function bounded(value: string): string {
  if (value.length > 10000) throw safe("invalid_csv");
  return value.trim();
}

function safe(code: string): TelegramSafeError {
  return new TelegramSafeError(
    code,
    "The source could not be processed safely.",
  );
}

function object(value: unknown): Record<string, unknown> {
  if (!isObject(value)) throw safe("extraction_failed");
  return value;
}

function string(value: unknown): string {
  if (typeof value !== "string") throw safe("extraction_failed");
  return value;
}

function nullable(value: unknown): string | null {
  return value == null ? null : string(value);
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function numberOrNull(value: unknown): number | null {
  return Number.isSafeInteger(value) && Number(value) >= 0
    ? Number(value)
    : null;
}

async function safeReply(
  gateway: TelegramGateway,
  chatId: number,
  text: string,
): Promise<void> {
  try {
    await gateway.send(chatId, text);
  } catch { /* Telegram delivery does not alter ingestion safety */ }
}

function response(status: number): Response {
  return new Response("ok", {
    status,
    headers: { "Content-Type": "text/plain", "Cache-Control": "no-store" },
  });
}
