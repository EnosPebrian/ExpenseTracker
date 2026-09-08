# BETA-08H1A Hosted Schema Rollout Checkpoint

Date: 2026-09-07

## Verdict

**BETA-08H1A Hosted Schema Rollout PASS.**

The six intended database migrations were backed up, dry-run, locally
revalidated, and applied in order to the linked `pilgrim-tracker-dev` project.
Existing hosted entity counts were preserved and the BETA-08L0 category
identity checks passed. Post-deployment privilege verification initially found
a serious Telegram RPC exposure and correctly stopped the rollout. The ordered
BETA-08H1A1 ACL-only migration subsequently removed all anonymous Telegram RPC
execution and authenticated execution of all service-only Telegram RPCs.
Direct ACL checks, authorization smoke checks, 224 pgTAP assertions, and the
security advisor now confirm the intended privilege matrix.

This is not BETA-08H1 Hosted Deployment PASS and not Owner Runtime PASS.

## Project and recovery point

- Project: `pilgrim-tracker-dev`
- Project ref: `jylclfebdeaywfdwabph`
- Project status before rollout: `ACTIVE_HEALTHY`
- Logical backup timestamp: `20260907-201605`
- Backup directory:
  `C:\Users\enosp\PilgrimTrackerBackups\pre-beta08h1a-20260907-201605`
- The directory is outside the Git working tree. All dump commands succeeded;
  every file was non-empty and readable.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `roles.sql` | 431 | `0DECD601FAA70260A3A31E8CE63208CC4A4C1F99921BC6F3ED4FAF1CD980DA3A` |
| `schema.sql` | 101834 | `70011CBE724AB81391AA67AAA19D1C98D801A9E8FDBFDF6866A4DDBC33B84C14` |
| `data.sql` | 126712 | `A4AECD4F462EE20CBBD542F3C16A146F22893C51B09C33C51E892170712BF6E1` |
| `history_schema.sql` | 887 | `18B99FBBB3EC9FBB964BB255A56171329ACD99B6977ECE2ADDD89FDF5AA5105B` |
| `history_data.sql` | 81122 | `9251D4770ECD7F01642F66C16503A27C4F258FF0EC129545F76E0FF9590CCA2B` |

No SQL contents, secrets, owner identities, or financial values were recorded.

## Migration ancestry and execution

Remote history initially ended at
`202608020001_beta07a_monthly_category_budgets`. The exact pending repository
chain was:

1. `202608190001_beta08e_transaction_import_rules.sql`
2. `202608200001_beta08f0_canonical_internal_transfers.sql`
3. `202608210001_beta08g_import_review_inbox.sql`
4. `202608220001_beta08g1_deferred_import_identity.sql`
5. `202608230001_beta08h_telegram_ingestion.sql`
6. `20260904141514_beta08l0_transaction_category_identity.sql`

The dry run listed only these six migrations. `supabase db push` applied all
six successfully and in this order. The final local and remote histories match
through `20260904141514`; no gap, duplicate repair, reset, seed, or manual
history edit occurred.

Before the dry run, review found newly introduced trigger validators whose
default function execution privileges were broader than intended. The pending
migration files were narrowly hardened to revoke validator execution from
`PUBLIC`, `anon`, and `authenticated`. Local `supabase db reset` and all 192
pgTAP assertions then passed. The full Flutter suite was not rerun because no
Dart source changed.

## Privacy-safe data comparison

| Measure | Before | After |
| --- | ---: | ---: |
| Database bytes | 13872275 | 14511251 |
| Auth users | 2 | 2 |
| Books | 1 | 1 |
| Book memberships | 2 | 2 |
| Accounts | 3 | 3 |
| Categories | 6 | 6 |
| Transactions | 27 | 27 |
| Monthly category budgets | 8 | 8 |

All pre-existing entity counts remained equal. The expected new infrastructure
tables started empty: transaction import rules, transfer links, import review
sessions, import review drafts, Telegram connections, Telegram pairing tokens,
and Telegram ingestion events each contained zero rows.

## Hosted structure and category identity

- BETA-08E transaction import rule table and user policies exist.
- BETA-08F0 canonical transfer link table and user policies exist.
- BETA-08G Import Review session/draft tables and policies exist.
- BETA-08G1 deferred identity binding exists and
  `deterministic_transaction_id` is nullable.
- BETA-08H connection, pairing-token, ingestion-event tables and RPCs exist.
- BETA-08L0 preserves non-null snapshot `category`, adds nullable
  `category_id`, and installs its identity validation.
- Transactions: 27 total; 25 have `category_id`; 2 retain null
  `category_id`; 0 non-null identities are dangling, cross-household, or type
  incompatible.
- All seven new infrastructure tables have RLS enabled. Seventeen expected
  user-facing policies are present. Telegram pairing-token and ingestion-event
  tables have no client table grants and intentionally have no client policies.
- The newly reviewed trigger validators are not executable by `anon` or
  `authenticated`.

## Security correction

Initial direct hosted privilege checks and the Supabase security advisor agreed
that all eight BETA-08H Telegram `SECURITY DEFINER` RPCs were executable by
`anon`. The five service-only ingestion/pairing RPCs were also executable by
`authenticated`. The stop gate prevented this checkpoint from passing.

The original migration revoked `PUBLIC`, but hosted role-specific default grants
to `anon` and `authenticated` remained. The ordered migration
`20260907143317_beta08h1a1_telegram_rpc_privileges.sql` now explicitly revokes
the affected roles and grants only the intended callers. Final hosted counts
are: anonymous executable 0, authenticated user-facing executable 3,
authenticated service-only executable 0, service-role executable 8, and
`PUBLIC` executable ACL 0. No function body, RLS policy, or business row changed.

The advisor no longer reports anonymous Telegram RPC access or authenticated
service-only Telegram access. Its remaining three authenticated Telegram RPC
warnings are intended client APIs whose bodies enforce authentication and
household authorization. Pre-existing findings remain separately classified:
three protected
sync tables with RLS but no client policies, two functions with mutable
`search_path`, intended authenticated `SECURITY DEFINER` application RPCs and
older trigger-helper execution warnings, plus leaked-password protection being
disabled. The new expected information notices for Telegram pairing/ingestion
tables reflect service-only RLS isolation; they are not the blocking defect.

## Deferred work

- No Edge Function was deployed.
- No OpenAI or Telegram secret was configured.
- No Telegram webhook or external API call was made.
- No owner runtime or consolidated acceptance was run.
- BETA-08H1 Hosted Deployment remains incomplete.
- BETA-08L0 Engineering and this hosted schema rollout pass; separately scoped
  BETA-08L development may begin.
