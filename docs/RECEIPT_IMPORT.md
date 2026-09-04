# Receipt / Invoice Import

BETA-08C adds reviewed transaction ingestion from one JPEG, PNG, or supported
WebP image. Android can capture a photo or use gallery/files; desktop and web
use the scoped file picker. The 12 MB limit, non-empty bytes, MIME magic, and
image dimensions are checked before upload.

## Safe flow

The client computes SHA-256 over the original image, then sends the bytes in
one authenticated request to `extract-financial-document`. The image is held
only in memory, never receives a public URL, is not written to SQLite, and is
not retained by Pilgrim Tracker after the request. Provider credentials and
model selection remain server-side.

Strict extraction returns merchant, local calendar date/time, currency,
subtotal/tax/service/discount/final total, reference, payment hint, transient
line items, confidence, and warnings. All output is untrusted. Pilgrim's local
date/money/enum/text validation remains authoritative. Missing date or total
produces a blocked draft for manual correction; today is never substituted.

One receipt creates one expense draft by default. Line items do not create
split transactions or schema records. Invoices display a payment warning and
never create liabilities. The user confirms the destination account and
category. Payment hints never select an account and the provider never assigns
internal category IDs.

## Identity and commit

The document hash, household, confirmed account, and stable receipt row key
feed the existing UUIDv5 import identity. Review edits do not change it.
Repeated identical images become already-imported records; visually different
copies remain protected by local semantic duplicate analysis. Confirmation
uses the existing atomic ordinary-transaction/outbox path. Local-only
households remain local-only; extraction authentication does not link them.

Extraction requires connectivity and an authenticated configured gateway.
Selection can happen offline, but v1 does not retain an offline photo queue.
Retry is explicit and no financial mutation occurs before confirmation.

## Deterministic category suggestion

The extractor does not choose a Pilgrim category. Its optional merchant name is
carried as a source-neutral `merchantHint` and may match an explicit local
household rule. The suggestion remains reviewable, requires the ordinary
transaction confirmation, and makes no additional AI request.

## Internal-transfer review

Receipt drafts enter the same post-duplicate matcher as CSV and statement
drafts. Only exact same-currency opposite movements between different household
accounts qualify; receipt text and source identity remain unchanged.

## Save for later

Receipt and invoice extraction may save normalized drafts to Import Inbox and
resume them in the shared editor. Merchant/date summary metadata is retained
only where useful; the image, provider response, and extraction prompt remain
transient and are unavailable on a secondary device.

Telegram photos and JPEG/PNG/WebP documents default to this existing extraction
contract. Exact caption `/statement` changes routing; `/receipt` keeps receipt
routing. Bytes and provider responses remain transient. The normalized receipt
is delivered to Inbox with no account, final ID, or financial mutation.
