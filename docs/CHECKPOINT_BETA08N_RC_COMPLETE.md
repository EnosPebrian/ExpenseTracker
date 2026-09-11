# PT-BETA-08N-RC Hosted Rollout Checkpoint

**Date:** 2026-09-11
**Hosted rollout:** PASS
**Owner/runtime acceptance:** PENDING / NOT RUN
**Final work-item state:** BLOCKED_OWNER

The linked `pilgrim-tracker-dev` project (`jylclfebdeaywfdwabph`) was verified
healthy. Its history matched the repository through `20260907233238`; the only
pending migrations were the explicitly authorized ordered pair:

1. `20260908124412_beta08m0_transaction_note_reference.sql`
2. `20260910054452_beta08n0_brokerage_metadata.sql`

Both migrations are additive. Review found no table drop, truncation, business-
row rewrite, RLS-policy change, migration-history edit, or Edge Function
deployment. BETA-08M0 replaces the established sync functions while preserving
their security mode/search path and adds nullable note/reference fields. N0
adds nullable brokerage attribution, validation/context triggers, and wrapper
functions with explicit client-execution revocation.

## Local gates

- Clean `supabase db reset`: PASS through both authorized migrations.
- BETA-08M0 pgTAP: 23/23 PASS.
- BETA-08N0 pgTAP: 24/24 PASS.
- Full pgTAP: 314/314 PASS across 15 files.

## Recovery point

The pre-DDL logical recovery point is outside the repository:

`C:\Users\enosp\PilgrimTrackerBackups\pre-beta08nrc-20260911-172323`

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `roles.sql` | 431 | `0DECD601FAA70260A3A31E8CE63208CC4A4C1F99921BC6F3ED4FAF1CD980DA3A` |
| `schema.sql` | 166256 | `DE591C4767E604E0D9A5CCAF0FB7DF91E3019678158F2CFFCDEE94E781510680` |
| `data.sql` | 134906 | `B3546E853726AFEB88BD2A0F050629A9F5BCED351E90724805824201FC767FAA` |
| `history_schema.sql` | 887 | `18B99FBBB3EC9FBB964BB255A56171329ACD99B6977ECE2ADDD89FDF5AA5105B` |
| `history_data.sql` | 151657 | `C2ABF477907193560D66C3EE162E49F9F33A36C633A140D57B22304A69DFED7A` |

All five dump commands succeeded; every artifact is non-empty. No credential,
dump content, or owner financial value is stored in Git.

## Hosted deployment and reconciliation

The final dry run listed exactly the two authorized migrations. Normal ordered
`supabase db push --linked --yes` applied BETA-08M0 then BETA-08N0. Final local
and hosted migration histories match through `20260910054452`.

| Privacy-safe measure | Before | After |
| --- | ---: | ---: |
| Database bytes | 14699667 | 14879891 |
| Auth users | 2 | 2 |
| Books | 1 | 1 |
| Book memberships | 2 | 2 |
| Household members | 2 | 2 |
| Accounts | 3 | 3 |
| Categories | 6 | 6 |
| Transactions | 28 | 28 |
| Asset definitions | 5 | 5 |
| Brokerage accounts | 0 | 0 |

Existing rows remain intact. Existing transactions received null note,
reference, and brokerage metadata; no financial row or identity was created,
deleted, or rewritten.

Hosted verification confirmed two nullable note/reference columns, four
nullable brokerage columns, five expected constraints, two brokerage triggers,
all six fields in the transaction initial-sync allowlist, transaction RLS still
enabled with four policies, anonymous push denied, authenticated push allowed,
and internal sync/validator helpers denied to both anonymous and authenticated
clients. The transaction-wrapped hosted pgTAP runs passed every structural,
sync, RLS, ACL, and cross-household assertion; each file's sole mismatch was
its clean-database absolute transaction-count assertion (hosted totals include
the 28 pre-existing rows). Rollback was confirmed by unchanged post-run counts.

The post-deployment security advisor introduced no new severe finding. Its
remaining findings were already present in the pre-deployment snapshot; the
previous authenticated `apply_sync_operation` warning was removed by N0's
explicit ACL revocation.

SQLite remains v28 and encrypted backup remains v7. No production Dart, local
SQLite, backup, financial behavior, historical migration, secret, or Edge
Function changed in this rollout. Feature freeze remains active. The remaining
step is owner-run Windows/Android acceptance in `BETA08N_OWNER_ACCEPTANCE.md`.
