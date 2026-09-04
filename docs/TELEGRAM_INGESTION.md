# Telegram Ingestion

## Scope

BETA-08H adds a private-chat transport into the existing Import Review Inbox:

```text
Telegram attachment -> authenticated gateway -> ImportReviewSession
                    -> unresolved ImportReviewDraft -> user review in Pilgrim
```

The gateway never writes transactions, transfer links, budgets, tithe output,
or financial outbox operations. Telegram cannot choose an account, category,
duplicate decision, or transfer decision. Only `/start`, `/help`, `/link
<token>`, `/unlink`, `/receipt`, and `/statement` routing are supported.

## Sources

- Telegram photos and JPEG/PNG/WebP documents default to receipt extraction.
- Exact caption `/statement` routes one image as a bank statement; `/receipt`
  retains receipt routing.
- Unlocked PDFs default to bank-statement extraction.
- Only canonical Pilgrim CSV (`date,description,amount,type` plus optional
  `category,reference,note`) is accepted. Mapping stays in the app.
- Arbitrary URLs, archives, office files, audio, video, protected PDFs, empty
  files, disguised files, and unsupported MIME types are rejected.

The source limit is 20 MB; canonical CSV retains its 10 MB limit. Metadata is
checked before download and actual bytes are checked afterward. Downloads use
only Telegram `file_id`/`getFile` paths. Exact source bytes are SHA-256 hashed,
parsed or extracted transiently, then released. Source bytes, token-bearing
file URLs, provider payloads, and webhook payloads are not retained.

## Inbox identity

Each remote row receives a stable workflow UUID, exact-byte source fingerprint,
canonical source-row key, and row fingerprint. Destination account,
`deterministicTransactionId`, and identity-account binding remain null. On
opening the Inbox, existing BETA-08G1 account selection finalizes the canonical
BETA-08B UUIDv5 identity and reruns rules, duplicates, and transfer matching.
No TypeScript financial UUID implementation exists.

Telegram `update_id` is separate delivery idempotency. Repeated delivery of the
same update is claimed once. The same bytes in a later message may form another
review session with the same source fingerprint; the app's canonical identity
and duplicate analysis protect financial commit after account selection.

## Processing

The webhook authenticates and claims an event synchronously. Supabase
`EdgeRuntime.waitUntil` owns processing when available. The handler otherwise
awaits the same task, avoiding an unsafe detached promise. Replies contain only
safe receipt counts or generic errors and never echo financial details.

V1 does not reconstruct Telegram media groups. Multi-page statements should be
sent as one unlocked PDF or imported directly in Pilgrim Tracker.
