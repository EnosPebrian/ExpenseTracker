# BETA-08H Deployment Guide

Status: **SAFETY BLOCKED IN BETA-08H1 READ-ONLY PREFLIGHT — NOT DEPLOYED**.

The 2026-08-31 preflight confirmed the expected linked project
`pilgrim-tracker-dev` (`jylclfebdeaywfdwabph`), but Supabase reported it as
inactive. Remote migration history could not be read, no managed recovery point
was listed, and all four required BETA-08H server secrets were missing. No
hosted mutation occurred. See `CHECKPOINT_BETA08H1_DEPLOYMENT.md` before using
the deployment sequence below.

Apply undeployed migrations in repository order:

1. `202608190001_beta08e_transaction_import_rules.sql`
2. `202608200001_beta08f0_canonical_internal_transfers.sql`
3. `202608210001_beta08g_import_review_inbox.sql`
4. `202608220001_beta08g1_deferred_import_identity.sql`
5. `202608230001_beta08h_telegram_ingestion.sql`

Then deploy `extract-financial-document`, `telegram-connection`, and
`telegram-webhook`. Set these server secrets through the deployment platform,
never source control or Flutter:

```text
OPENAI_API_KEY
OPENAI_EXTRACTION_MODEL
TELEGRAM_BOT_TOKEN
TELEGRAM_WEBHOOK_SECRET
```

Register the Telegram webhook only after functions and secrets are healthy.
Configure Telegram's `secret_token` to the same high-entropy webhook secret and
verify a wrong/missing header returns 401 before enabling owner tests. Confirm
`telegram-connection` keeps JWT verification enabled and only
`telegram-webhook` uses the external-webhook configuration.

Smoke-test with synthetic private data: link, canonical CSV, receipt image,
unlocked statement PDF, duplicate update delivery, oversized rejection,
disconnect, and post-membership-revocation rejection. Confirm only Inbox and
server integration tables change before explicit in-app commit. Do not retain
test attachments or log secrets.
