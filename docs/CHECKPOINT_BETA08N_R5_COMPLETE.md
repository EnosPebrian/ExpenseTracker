# PT-BETA-08N-R5 Hosted Rollout — Complete

**Date:** 2026-09-21

**Project:** `pilgrim-tracker-dev` (`jylclfebdeaywfdwabph`)

**Engineering/hosted verdict:** PASS

**Next state:** BLOCKED_OWNER — owner acceptance PENDING / NOT RUN

## Deployed migration chain

1. `20260915004307_brokerage_settlement_evidence.sql`
2. `20260916000331_beta08n_interest_activity.sql`
3. `20260921144802_beta08n_settlement_delete_acl.sql`

The third migration was separately authorized by ARCH-20260921-01 after the
first hosted pass exposed an inherited authenticated DELETE grant. It changes
only that ACL: authenticated clients retain SELECT, INSERT and UPDATE and no
longer have direct DELETE. Existing migrations were not edited. Versioned
UPDATE/deleted-at tombstones remain the deletion mechanism.

## Validation

- clean local migration reset/replay: PASS
- focused settlement ACL/reconciliation/tombstone pgTAP: 25/25 PASS
- focused Interest pgTAP: 13/13 PASS
- full local pgTAP: 352/352 PASS across 17 files
- hosted settlement + Interest transaction-wrapped pgTAP: 38/38 PASS
- hosted ACL/RLS/policy/history/count verification: 5/5 PASS
- migration dry-run: exactly `20260921144802` pending
- final migration history: local and hosted aligned through `20260921144802`
- pre/post database lint: identical; no new regression
- Git diff checks: PASS

The hosted cross-household negative case is rejected by the settlement domain
validator (`P0001 Incompatible settlement account`) before RLS. The write is
blocked and household isolation remains intact. Direct authenticated DELETE is
rejected with privilege denial. Settlement insert, reconciliation update,
bootstrap/change feed, versioned tombstone sync and zero-financial-effect
behavior all pass.

## Fresh recovery point

External directory:

`C:\Users\enosp\PilgrimTrackerBackups\pre-beta08nr5-acl-20260921-215323`

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `roles.sql` | 431 | `0DECD601FAA70260A3A31E8CE63208CC4A4C1F99921BC6F3ED4FAF1CD980DA3A` |
| `schema.sql` | 186902 | `72E03BDA31E36E8140E08663DA955FD41E5C47001DF98701CC8B2832A1BCF11F` |
| `data.sql` | 218344 | `98BEF8D74069161C410FD242CA3CB1673F46D73D6369A14D0366F0D96BAFE812` |
| `history_schema.sql` | 887 | `18B99FBBB3EC9FBB964BB255A56171329ACD99B6977ECE2ADDD89FDF5AA5105B` |
| `history_data.sql` | 200665 | `9AFA9D8CA3A8F414A4B4CBAC2F174E93A241CBA4AB1D061319DB43157A0EE205` |

All five dump commands succeeded; every artifact is non-empty. No dump or
credential is stored in Git.

## Data preservation

| Privacy-safe measure | Before | After |
| --- | ---: | ---: |
| Books | 1 | 1 |
| Memberships | 2 | 2 |
| Household members | 2 | 2 |
| Accounts | 4 | 4 |
| Brokerage accounts | 1 | 1 |
| Categories | 7 | 7 |
| Transactions | 80 | 80 |
| Asset definitions | 10 | 10 |
| Settlement evidence | 0 | 0 |

No business row changed. The migration is privilege-only and hosted tests ran
inside rolled-back transactions.

## Remaining gate

Feature freeze remains active. Owner acceptance must not be inferred from this
checkpoint. The next owner action is to rerun the real 125-row RDN CSV on Windows
and then execute the remaining Windows/Android matrix in
`docs/BETA08N_OWNER_ACCEPTANCE.md`.
