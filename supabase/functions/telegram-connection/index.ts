import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { safeJson, TelegramSafeError } from "../_shared/telegram_security.ts";
import { createPairingMaterial, parseConnectionOperation } from "./_shared.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return safeJson({ ok: true });
  if (request.method !== "POST") {
    return safeJson({ error: "Method not allowed." }, 405);
  }
  try {
    const url = Deno.env.get("SUPABASE_URL")?.trim();
    const key = (Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
      Deno.env.get("SUPABASE_ANON_KEY"))?.trim();
    const authorization = request.headers.get("authorization");
    if (!url || !key || !authorization) {
      return safeJson({ error: "Authentication required." }, 401);
    }
    const client = createClient(url, key, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await client.auth.getUser();
    if (authError || !authData.user) {
      return safeJson({ error: "Authentication required." }, 401);
    }
    const operation = parseConnectionOperation(await request.json());
    if (operation.operation === "status") {
      const { data, error } = await client.rpc("telegram_connection_status", {
        p_book_id: operation.bookId,
      });
      if (error) throw error;
      const row = Array.isArray(data) ? data[0] : data;
      return safeJson({
        connected: row?.connected === true,
        connected_at: row?.connected_at ?? null,
      });
    }
    if (operation.operation === "disconnect") {
      const { error } = await client.rpc("disconnect_telegram_connection", {
        p_book_id: operation.bookId,
      });
      if (error) throw error;
      return safeJson({ connected: false });
    }
    const material = await createPairingMaterial();
    const { error } = await client.rpc("issue_telegram_pairing_token", {
      p_book_id: operation.bookId,
      p_member_id: operation.memberId,
      p_token_hash: material.tokenHash,
      p_expires_at: material.expiresAt.toISOString(),
    });
    if (error) throw error;
    return safeJson({
      command: `/link ${material.token}`,
      expires_at: material.expiresAt.toISOString(),
    });
  } catch (error) {
    if (error instanceof TelegramSafeError) {
      return safeJson({ error: error.safeMessage }, error.status);
    }
    return safeJson({
      error: "Telegram connection is temporarily unavailable.",
    }, 503);
  }
});
