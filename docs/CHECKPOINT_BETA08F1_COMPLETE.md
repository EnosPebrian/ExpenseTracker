# BETA-08F1 Engineering Checkpoint

Status: engineering implementation complete; owner runtime acceptance not run.

BETA-08F1 implements deterministic internal-transfer matching and explicit review for draft-to-existing, existing-to-existing, and draft-to-draft flows while reusing BETA-08F0 canonical transaction legs and `transfer_links`.

Key invariants:

- SQLite remains version 23.
- Portable backup remains version 4.
- No Supabase migration or hosted deployment was added.
- Exact amount, same currency, opposite direction, different accounts, same household, live ordinary rows, unpaired state, and a ±2 local-calendar-day window are mandatory.
- Duplicate detection and possible-deleted safety precede import matching.
- Deterministic import IDs and source fingerprints are preserved.
- Confirmed imported pairs and their links commit atomically with in-transaction stale-version checks.
- Candidate/rejection state is transient and does not synchronize or back up.
- Canonical report, budget, tithe, balance, backup, restore, and sync semantics remain unchanged.

The mandatory BETA-08G Phase 0 rerun passed both `flutter build windows
--debug` and `flutter build apk --debug`. BETA-08F1 and consolidated BETA-08F
are therefore Engineering PASS. Consolidated owner acceptance remains deferred
with BETA-08A1 through BETA-08F0.
