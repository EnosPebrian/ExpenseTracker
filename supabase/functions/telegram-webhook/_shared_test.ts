import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  handleTelegramWebhook,
  parseCanonicalCsv,
  type TelegramClaim,
  type TelegramGateway,
} from "./_shared.ts";

class FakeGateway implements TelegramGateway {
  claims = 0;
  downloads = 0;
  extractions = 0;
  inboxes: Array<Record<string, unknown>> = [];
  replies: string[] = [];
  finished: string[] = [];
  claimResult: TelegramClaim = {
    claimed: true,
    connection_id: "11111111-1111-4111-8111-111111111111",
    currency_code: "IDR",
  };
  linked = true;
  bytes = new TextEncoder().encode(
    "date,description,amount,type,category,reference,note\n2026-08-31,Coffee,12000,expense,Food,R1,Test\n",
  );
  mimeExtraction: Record<string, unknown> = {
    result: {
      document_type: "receipt",
      merchant_name: "Cafe",
      transaction_date: "2026-08-31",
      total: "12000",
      receipt_number: "R1",
    },
  };
  async claim(): Promise<TelegramClaim> {
    this.claims++;
    return this.claimResult;
  }
  async consumeToken(): Promise<boolean> {
    return this.linked;
  }
  async revoke(): Promise<boolean> {
    return true;
  }
  async finish(
    _id: number,
    status: "completed" | "failed" | "ignored",
    code?: string,
  ): Promise<void> {
    this.finished.push(`${status}:${code ?? ""}`);
  }
  async createInbox(input: {
    updateId: number;
    connectionId: string;
    session: Record<string, unknown>;
    drafts: Record<string, unknown>[];
  }): Promise<string> {
    this.inboxes.push(input);
    return String(input.session.id);
  }
  async getFile(): Promise<{ path: string; size: number | null }> {
    return { path: "documents/test.csv", size: this.bytes.length };
  }
  async download(): Promise<Uint8Array> {
    this.downloads++;
    return this.bytes;
  }
  async extract(): Promise<Record<string, unknown>> {
    this.extractions++;
    return this.mimeExtraction;
  }
  async send(_chatId: number, text: string): Promise<void> {
    this.replies.push(text);
  }
}

const secret = "test-webhook-secret";

function update(options: {
  updateId?: number;
  chatType?: string;
  text?: string;
  caption?: string;
  document?: Record<string, unknown>;
  photo?: Record<string, unknown>[];
} = {}): Record<string, unknown> {
  return {
    update_id: options.updateId ?? 1,
    message: {
      message_id: 9,
      from: { id: 42, is_bot: false },
      chat: { id: 42, type: options.chatType ?? "private" },
      ...(options.text != null ? { text: options.text } : {}),
      ...(options.caption != null ? { caption: options.caption } : {}),
      ...(options.document != null ? { document: options.document } : {}),
      ...(options.photo != null ? { photo: options.photo } : {}),
    },
  };
}

function request(body: unknown, header: string | null = secret): Request {
  const headers = new Headers({ "Content-Type": "application/json" });
  if (header != null) headers.set("x-telegram-bot-api-secret-token", header);
  return new Request("http://local/telegram", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

const csvDocument = {
  file_id: "csv-file",
  file_name: "transactions.csv",
  mime_type: "text/csv",
  file_size: 100,
};

Deno.test("webhook rejects missing and incorrect secrets before claiming", async () => {
  for (const header of [null, "wrong"]) {
    const gateway = new FakeGateway();
    assertEquals(
      (await handleTelegramWebhook(request(update(), header), gateway, secret))
        .status,
      401,
    );
    assertEquals(gateway.claims, 0);
  }
});

Deno.test("webhook accepts correct secret and ignores group messages", async () => {
  const gateway = new FakeGateway();
  assertEquals(
    (await handleTelegramWebhook(
      request(update({ chatType: "group" })),
      gateway,
      secret,
    )).status,
    200,
  );
  assertEquals(gateway.claims, 0);
});

Deno.test("duplicate update does not process twice", async () => {
  const gateway = new FakeGateway();
  gateway.claimResult = { claimed: false, reason: "duplicate" };
  await handleTelegramWebhook(
    request(update({ document: csvDocument })),
    gateway,
    secret,
  );
  assertEquals(gateway.downloads, 0);
  assertEquals(gateway.inboxes.length, 0);
});

Deno.test("valid and invalid pairing are handled without exposing IDs", async () => {
  const gateway = new FakeGateway();
  await handleTelegramWebhook(
    request(update({ text: "/link abcdefghijklmnopqrstuvwxyz" })),
    gateway,
    secret,
  );
  assertEquals(gateway.replies.length, 1);
  assert(gateway.replies[0].includes("connected"));
  const invalid = new FakeGateway();
  invalid.linked = false;
  await handleTelegramWebhook(
    request(update({ text: "/link abcdefghijklmnopqrstuvwxyz" })),
    invalid,
    secret,
  );
  assertEquals(invalid.replies.length, 1);
  assert(invalid.replies[0].includes("invalid or expired"));
});

Deno.test("canonical CSV creates unresolved Inbox drafts only", async () => {
  const gateway = new FakeGateway();
  await handleTelegramWebhook(
    request(update({ document: csvDocument })),
    gateway,
    secret,
  );
  assertEquals(gateway.inboxes.length, 1);
  const inbox = gateway.inboxes[0] as {
    session: Record<string, unknown>;
    drafts: Record<string, unknown>[];
  };
  assertEquals(inbox.session.source_type, "csv");
  assertEquals(inbox.drafts.length, 1);
  const draft = inbox.drafts[0];
  assertEquals("deterministic_transaction_id" in draft, false);
  assertEquals("deterministic_transaction_account_id" in draft, false);
  assertEquals(draft.source_row_key, "2");
  assertEquals(String(draft.source_row_identity).length, 64);
});

Deno.test("canonical CSV supports BOM, quotes, and escaped fields", async () => {
  const rows = await parseCanonicalCsv(
    new TextEncoder().encode(
      '\uFEFFdate,description,amount,type\n2026-08-31,"Cafe, ""East""",12000,expense\n',
    ),
    "IDR",
  );
  assertEquals(rows.length, 1);
  assertEquals(rows[0].description, 'Cafe, "East"');
  assertEquals(rows[0].amountMinor, 12000);
});

Deno.test("noncanonical and malformed CSV are rejected without Inbox rows", async () => {
  for (
    const content of [
      "when,memo,value\n2026-08-31,Coffee,1\n",
      'date,description,amount,type\n2026-08-31,"broken,1,expense\n',
    ]
  ) {
    const gateway = new FakeGateway();
    gateway.bytes = new TextEncoder().encode(content);
    await handleTelegramWebhook(
      request(update({ document: csvDocument })),
      gateway,
      secret,
    );
    assertEquals(gateway.inboxes.length, 0);
    assert(gateway.finished[0].startsWith("failed:"));
  }
});

Deno.test("metadata size limits reject before download", async () => {
  const gateway = new FakeGateway();
  await handleTelegramWebhook(
    request(update({
      document: { ...csvDocument, file_size: 10 * 1024 * 1024 + 1 },
    })),
    gateway,
    secret,
  );
  assertEquals(gateway.downloads, 0);
});

Deno.test("actual-byte size and zero-byte checks reject safely", async () => {
  const zero = new FakeGateway();
  zero.bytes = new Uint8Array();
  await handleTelegramWebhook(
    request(update({ document: { ...csvDocument, file_size: 0 } })),
    zero,
    secret,
  );
  assertEquals(zero.inboxes.length, 0);
  await assertRejects(() => parseCanonicalCsv(new Uint8Array([0xff]), "IDR"));
});

Deno.test("arbitrary URL text is never downloaded", async () => {
  const gateway = new FakeGateway();
  await handleTelegramWebhook(
    request(update({ text: "https://example.com/statement.pdf" })),
    gateway,
    secret,
  );
  assertEquals(gateway.downloads, 0);
  assertEquals(gateway.inboxes.length, 0);
});

Deno.test("image defaults to receipt and statement caption overrides routing", async () => {
  for (const statement of [false, true]) {
    const gateway = new FakeGateway();
    gateway.bytes = new Uint8Array([0xff, 0xd8, 0xff, 1]);
    if (statement) {
      gateway.mimeExtraction = {
        result: {
          transactions: [{
            transaction_date: "2026-08-31",
            posting_date: null,
            description: "Transfer",
            amount: "12000",
            direction: "debit",
            reference: null,
          }],
        },
      };
    }
    await handleTelegramWebhook(
      request(update({
        caption: statement ? "/statement" : undefined,
        photo: [{ file_id: "image", file_size: 4 }],
      })),
      gateway,
      secret,
    );
    const inbox = gateway.inboxes[0] as { session: Record<string, unknown> };
    assertEquals(
      inbox.session.source_type,
      statement ? "bankStatement" : "receipt",
    );
    assertEquals(gateway.extractions, 1);
  }
});

Deno.test("PDF uses statement extraction and protected PDF is rejected", async () => {
  const gateway = new FakeGateway();
  gateway.bytes = new TextEncoder().encode("%PDF-1.7 safe");
  gateway.mimeExtraction = {
    result: {
      transactions: [{
        transaction_date: "2026-08-31",
        posting_date: null,
        description: "Debit",
        amount: "12000",
        direction: "debit",
        reference: null,
      }],
    },
  };
  const pdf = {
    file_id: "pdf",
    file_name: "statement.pdf",
    mime_type: "application/pdf",
    file_size: 13,
  };
  await handleTelegramWebhook(
    request(update({ document: pdf })),
    gateway,
    secret,
  );
  assertEquals(gateway.inboxes.length, 1);
  const protectedFile = new FakeGateway();
  protectedFile.bytes = new TextEncoder().encode("%PDF-1.7 /Encrypt");
  await handleTelegramWebhook(
    request(update({ document: pdf })),
    protectedFile,
    secret,
  );
  assertEquals(protectedFile.extractions, 0);
});

Deno.test("ZIP disguised as PDF and bad image magic are rejected", async () => {
  for (
    const bytes of [
      new Uint8Array([0x50, 0x4b, 3, 4]),
      new TextEncoder().encode("not-an-image"),
    ]
  ) {
    const gateway = new FakeGateway();
    gateway.bytes = bytes;
    const document = bytes[0] === 0x50
      ? {
        file_id: "x",
        file_name: "x.pdf",
        mime_type: "application/pdf",
        file_size: bytes.length,
      }
      : {
        file_id: "x",
        file_name: "x.png",
        mime_type: "image/png",
        file_size: bytes.length,
      };
    await handleTelegramWebhook(request(update({ document })), gateway, secret);
    assertEquals(gateway.inboxes.length, 0);
    assertEquals(gateway.extractions, 0);
  }
});

Deno.test("rate limiting happens before file download and extraction", async () => {
  const gateway = new FakeGateway();
  gateway.claimResult = { claimed: false, reason: "rate_limited" };
  await handleTelegramWebhook(
    request(update({ document: csvDocument })),
    gateway,
    secret,
  );
  assertEquals(gateway.downloads, 0);
  assertEquals(gateway.extractions, 0);
});

Deno.test("same bytes in new updates keep fingerprint but create distinct sessions", async () => {
  const gateway = new FakeGateway();
  await handleTelegramWebhook(
    request(update({ updateId: 1, document: csvDocument })),
    gateway,
    secret,
  );
  await handleTelegramWebhook(
    request(update({ updateId: 2, document: csvDocument })),
    gateway,
    secret,
  );
  const first = gateway.inboxes[0] as { session: Record<string, unknown> };
  const second = gateway.inboxes[1] as { session: Record<string, unknown> };
  assertEquals(
    first.session.source_fingerprint,
    second.session.source_fingerprint,
  );
  assert(first.session.id !== second.session.id);
});

Deno.test("all replies are privacy-minimal", async () => {
  const gateway = new FakeGateway();
  await handleTelegramWebhook(
    request(update({ document: csvDocument })),
    gateway,
    secret,
  );
  const reply = gateway.replies.join(" ");
  assert(!reply.includes("Coffee"));
  assert(!reply.includes("12000"));
  assert(!reply.includes("11111111"));
});
