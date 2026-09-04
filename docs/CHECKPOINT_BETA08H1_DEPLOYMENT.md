# BETA-08H1 Hosted Deployment Checkpoint

Date: 2026-08-31

Status: **SAFETY BLOCKED IN READ-ONLY PREFLIGHT**.

No hosted mutation, secret update, migration push, function deployment,
Telegram API call, release build, or owner runtime action was performed.

## Phase 0 result

- Linked project: `pilgrim-tracker-dev` (`jylclfebdeaywfdwabph`). This matches
  the repository's previously accepted private project.
- Supabase project status: `INACTIVE`.
- Local migration dry review: the only expected undeployed chain is:
  `202608190001_beta08e_transaction_import_rules.sql`,
  `202608200001_beta08f0_canonical_internal_transfers.sql`,
  `202608210001_beta08g_import_review_inbox.sql`,
  `202608220001_beta08g1_deferred_import_identity.sql`, and
  `202608230001_beta08h_telegram_ingestion.sql`.
- Remote migration history: **NOT VERIFIED**. The inactive database rejected
  the read-only login-role connection with a connection timeout.
- Hosted pre-deployment recovery point: **NOT AVAILABLE — STOPPED**. The
  management API reported WAL-G enabled, PITR disabled, and no listed backups.
- Required BETA-08H hosted secrets: `OPENAI_API_KEY`,
  `OPENAI_EXTRACTION_MODEL`, `TELEGRAM_BOT_TOKEN`, and
  `TELEGRAM_WEBHOOK_SECRET` are all **Missing**. Only Supabase-managed runtime
  secrets are present.
- Deployed Edge Functions: only the historical `create-book-invitation`
  function is present. None of the three BETA-08H functions is deployed.
- Telegram webhook state: **NOT CHECKED** because no bot token is available.
- Local `git diff --check`: **PASS** before preflight.

These conditions trigger the milestone's mandatory stop policy. In particular,
the project must not be resumed, migrations must not be applied, and functions
or webhook configuration must not proceed until remote ancestry and a
recoverable safety point can be verified.

## Required owner/platform action

1. Restore/reactivate the expected Supabase project through the normal project
   administration workflow.
2. Establish and verify a recoverable managed backup/snapshot or an already
   approved logical-backup procedure.
3. Supply the four required server values through the secure secret workflow;
   never send values in logs or documentation.
4. Re-run Phase 0. Continue only if remote migration history contains no drift
   and the dry-run contains exactly the E -> F0 -> G -> G1 -> H chain.

Engineering status for BETA-08A1 through BETA-08H remains **PASS**. Hosted
Deployment PASS and Consolidated Owner Runtime PASS are **NOT CLAIMED**.
