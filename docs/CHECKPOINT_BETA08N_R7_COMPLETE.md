# PT-BETA-08N-R7 Complete

**Date:** 2026-09-27

**Verdict:** Engineering PASS; owner runtime acceptance PENDING / NOT RUN

**Feature freeze:** ACTIVE

## Root cause and repair

Initial brokerage analysis already processed activities chronologically, but
review actions finalized only the edited row against persisted transactions.
Consequently, one-row instrument creation did not resolve the rest of the
statement, and later SELL/SPLIT rows could not see an earlier uncommitted BUY.

The planner now has one canonical full-preview replanning operation. An
explicit Map/Create decision propagates to compatible rows sharing normalized
symbol and currency. Replanning sorts by activity date and stable source row,
then validates each included draft against persisted history plus prior planned
postings. `AssetTradeValidator` remains authoritative; no position is persisted
before final atomic commit.

## Safety properties verified

- all nine brokerage activities coexist in one review session;
- one PTST creation resolves BUY, DIVIDEND, SELL and SPLIT;
- one deterministic definition is planned and committed;
- later SELL and SPLIT see the earlier included BUY;
- excluding or changing that BUY immediately invalidates dependent rows;
- oversells remain blocked;
- CSV source order cannot override chronological activity order;
- same symbol in a different currency is not resolved accidentally;
- an explicit existing-instrument mapping propagates safely;
- trusted IDX automatic staging remains intact;
- exact re-import has zero duplicate effect;
- atomic persistence, settlement and Interest behavior are unchanged.

## Verification

```text
focused brokerage/settlement/validation/duplicate/atomic tests: 97/97 PASS
flutter analyze: PASS
full Flutter suite: 1024/1024 PASS
flutter build web --debug: PASS
flutter build windows --debug: PASS
flutter build apk --debug: PASS
git diff --check: PASS
known warning: unchanged file_picker forward-looking Kotlin warning
```

No SQLite, Supabase, hosted, backup-format, accounting, settlement or Interest
semantics changed.

## Owner acceptance

R7 Windows and Android runtime acceptance remains **PENDING / NOT RUN**. The
exact procedure is recorded in `docs/BETA08N1_OWNER_ACCEPTANCE.md`. No
unexecuted owner check is marked PASS.
