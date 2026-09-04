import {
  buildProviderBody,
  extractOutputText,
  RequestValidationError,
  validateProviderResult,
  type ValidExtractionRequest,
} from "../extract-financial-document/_shared.ts";

export async function extractFinancialDocument(
  request: ValidExtractionRequest,
  options: {
    apiKey: string;
    model: string;
    fetcher?: typeof fetch;
    timeoutMs?: number;
  },
): Promise<Record<string, unknown>> {
  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    options.timeoutMs ?? 60000,
  );
  let response: Response;
  try {
    response = await (options.fetcher ?? fetch)(
      "https://api.openai.com/v1/responses",
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${options.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(buildProviderBody(request, options.model)),
        signal: controller.signal,
      },
    );
  } finally {
    clearTimeout(timeout);
  }
  if (!response.ok) {
    throw new RequestValidationError(
      "Extraction provider is temporarily unavailable.",
      response.status === 429 ? 429 : 502,
    );
  }
  const output = extractOutputText(await response.json());
  let parsed: unknown;
  try {
    parsed = JSON.parse(output);
  } catch {
    throw new RequestValidationError(
      "Provider returned invalid structured data.",
      502,
    );
  }
  return validateProviderResult(request.documentType, parsed);
}
