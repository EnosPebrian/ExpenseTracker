import {
  RequestValidationError,
  requireAuthorization,
  validateRequest,
} from "./_shared.ts";
import { extractFinancialDocument } from "../_shared/document_extraction_client.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }
  try {
    requireAuthorization(request.headers.get("authorization"));
    const valid = validateRequest(await request.json());
    const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim();
    const model = Deno.env.get("OPENAI_EXTRACTION_MODEL")?.trim();
    if (!apiKey || !model) {
      return json({ error: "Document extraction is not configured." }, 503);
    }
    return json(await extractFinancialDocument(valid, { apiKey, model }), 200);
  } catch (error) {
    if (error instanceof RequestValidationError) {
      return json({ error: error.message }, error.status);
    }
    if (error instanceof DOMException && error.name === "AbortError") {
      return json({ error: "Document extraction timed out." }, 504);
    }
    return json({ error: "Document extraction failed safely." }, 500);
  }
});

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
