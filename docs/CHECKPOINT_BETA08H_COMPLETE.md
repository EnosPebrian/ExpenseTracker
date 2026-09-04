# BETA-08H Engineering Checkpoint

Milestone: Secure Telegram Ingestion Gateway & Import Inbox Delivery.

Engineering implementation provides private-chat pairing, hashed expiring
single-use tokens, webhook secret verification, server-only bot credentials,
event idempotency, membership revalidation, rate limiting, transient attachment
validation, canonical CSV parsing, reused receipt/statement extraction, and
atomic delivery into existing Import Review Inbox entities.

Telegram leaves destination account and both final identity fields unresolved.
Existing BETA-08G1 performs later UUIDv5 finalization, duplicate analysis, rule
analysis, and transfer matching. No Telegram path creates financial records.

SQLite remains v25 and backup remains v4. The single BETA-08H Supabase
migration and all functions remain undeployed. Owner acceptance is NOT RUN.
See the final engineering report for the exact locally executed verification
results and `BETA08H_DEPLOYMENT.md` for the future deployment order.
