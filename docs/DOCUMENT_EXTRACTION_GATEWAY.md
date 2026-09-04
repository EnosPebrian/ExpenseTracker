# Secure Document Extraction Gateway

`extract-financial-document` is the one reusable Supabase Edge Function for
receipt/invoice and bank-statement extraction. Flutter never calls the AI
provider directly. Supabase JWT verification is enabled and the function also
rejects a missing bearer token.

Secrets are server-only:

- `OPENAI_API_KEY`
- `OPENAI_EXTRACTION_MODEL`

The function uses the OpenAI Responses API with multimodal `input_image` or
`input_file` content and strict JSON Schema structured output. The model is
configured by the environment. Requests use `store: false`, one provider call
per document session, a bounded timeout, and no category or duplicate AI call.

## Privacy and validation

The direct-byte architecture avoids Storage and public URLs. Source documents
exist only in client/function/provider request memory and Pilgrim Tracker does
not retain them. The function never fetches a caller URL, accepts a caller
prompt, logs source contents, returns secrets, or exposes internal prompts.

Receipt requests allow one validated image and 12 MB. Statement requests allow
one PDF or up to 50 ordered validated images and 25 MB total. MIME declarations
must match magic bytes. Provider output is strict-schema constrained and is
validated again before return. Document text is explicitly treated as
untrusted data; instructions embedded in an image/PDF cannot alter the server
instruction or output contract.

Errors are reduced to safe authentication, format, size, rate, timeout,
configuration, or temporary-service messages. Automated tests use synthetic
bytes and mocks and never call a paid provider. Provider cost depends on the
configured model and document size; no guaranteed price is embedded in the
app.

Deploy the function separately after setting the two secrets. This milestone
does not deploy it to hosted production automatically and adds no SQL migration.

BETA-08H extracts the provider request into a shared server client used by both
the authenticated extraction function and Telegram gateway. Telegram makes at
most one extraction call per document and adds no categorization, duplicate,
transfer, or routing AI call. Automated tests inject fakes and contact no paid
provider. Both extraction and Telegram functions remain undeployed.
