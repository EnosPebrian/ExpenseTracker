import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { extractFinancialDocument } from "../_shared/document_extraction_client.ts";
import type { TelegramGateway } from "./_shared.ts";
import { handleTelegramWebhook } from "./_shared.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN")?.trim() ?? "";
const webhookSecret = Deno.env.get("TELEGRAM_WEBHOOK_SECRET")?.trim() ?? "";
const openAiKey = Deno.env.get("OPENAI_API_KEY")?.trim() ?? "";
const extractionModel = Deno.env.get("OPENAI_EXTRACTION_MODEL")?.trim() ||
  "gpt-5-mini";

Deno.serve(async (request) => {
  if (!supabaseUrl || !serviceKey || !botToken || !webhookSecret) {
    return new Response("unavailable", { status: 503 });
  }
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const rpc = async <T>(
    name: string,
    params: Record<string, unknown>,
  ): Promise<T> => {
    const { data, error } = await admin.rpc(name, params);
    if (error) throw error;
    return data as T;
  };
  const telegram = async (method: string, body: Record<string, unknown>) => {
    const result = await fetch(
      `https://api.telegram.org/bot${botToken}/${method}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      },
    );
    if (!result.ok) throw new Error("telegram unavailable");
    const value = await result.json();
    if (!value?.ok) throw new Error("telegram rejected request");
    return value.result;
  };
  const runtime = (globalThis as unknown as {
    EdgeRuntime?: { waitUntil(task: Promise<void>): void };
  }).EdgeRuntime;
  const gateway: TelegramGateway = {
    claim: (input) =>
      rpc("telegram_claim_ingestion_event", {
        p_update_id: input.updateId,
        p_telegram_user_id: input.userId,
        p_telegram_chat_id: input.chatId,
        p_message_id: input.messageId,
        p_event_type: input.eventType,
      }),
    consumeToken: (input) =>
      rpc("telegram_consume_pairing_token", {
        p_update_id: input.updateId,
        p_token_hash: input.tokenHash,
        p_telegram_user_id: input.userId,
        p_telegram_chat_id: input.chatId,
      }),
    revoke: (input) =>
      rpc("telegram_revoke_connection", {
        p_update_id: input.updateId,
        p_telegram_user_id: input.userId,
        p_telegram_chat_id: input.chatId,
      }),
    finish: (updateId, status, code) =>
      rpc("telegram_finish_ingestion_event", {
        p_update_id: updateId,
        p_status: status,
        p_error_code: code ?? null,
      }),
    createInbox: (input) =>
      rpc("create_telegram_import_review", {
        p_update_id: input.updateId,
        p_connection_id: input.connectionId,
        p_session: input.session,
        p_drafts: input.drafts,
      }),
    getFile: async (fileId) => {
      const value = await telegram("getFile", { file_id: fileId });
      if (!value || typeof value.file_path !== "string") {
        throw new Error("file unavailable");
      }
      return {
        path: value.file_path,
        size: Number.isSafeInteger(value.file_size) ? value.file_size : null,
      };
    },
    download: async (path) => {
      const result = await fetch(
        `https://api.telegram.org/file/bot${botToken}/${path}`,
      );
      if (!result.ok) throw new Error("file unavailable");
      return new Uint8Array(await result.arrayBuffer());
    },
    extract: async (kind, file) => {
      if (!openAiKey) throw new Error("extraction unavailable");
      return await extractFinancialDocument(
        { documentType: kind, documents: [file] },
        { apiKey: openAiKey, model: extractionModel },
      );
    },
    send: async (chatId, text) => {
      await telegram("sendMessage", {
        chat_id: chatId,
        text,
        disable_web_page_preview: true,
        protect_content: true,
      });
    },
    ...(runtime?.waitUntil
      ? { schedule: (work: Promise<void>) => runtime.waitUntil(work) }
      : {}),
  };
  return await handleTelegramWebhook(request, gateway, webhookSecret);
});
