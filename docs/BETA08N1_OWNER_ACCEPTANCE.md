# BETA-08N1 Owner Acceptance

**Status:** NOT RUN

Run later on approved Windows and Android builds with disposable broker data
and a current encrypted backup:

1. Import a canonical UTF-8 brokerage CSV containing all nine supported
   activities and verify the preview before commit.
2. Import an external CSV, map every relevant column explicitly, and confirm
   date, money, reference, and note values.
3. Verify an unknown activity stays `UNRESOLVED`, blocks commit while included,
   and proceeds only after an explicit activity choice.
4. Verify an unknown symbol offers **Map to existing** and **Create compatible
   asset definition**, and that neither choice occurs silently.
5. Confirm BUY/SELL positions, basis, cash, fees, taxes, and realized gain agree
   with the manual N0 ledger; check a broker-P&L disagreement warning.
6. Confirm DEPOSIT/WITHDRAWAL create one canonical transfer each and do not
   affect income, spending, return, budgets, or Tithe Due.
7. Re-import the same file/account and confirm zero new financial rows and zero
   new pending sync operations.
8. Work offline, commit, reconnect, and confirm the other device receives one
   converged set; bootstrap a new device and compare positions and cash.
9. Validate and restore an encrypted v7 backup, then clone it, and verify all
   imported brokerage history and account/instrument references.
10. Check the review screen at intended Windows and Android sizes for overflow,
    readable warnings, explicit inclusion, and disabled unresolved commit.

Do not mark owner acceptance PASS until these runtime checks are completed.

## PT-BETA-08N-R7 session replanning acceptance

**Status:** PENDING / NOT RUN

Use a disposable statement containing DEPOSIT, BUY, DIVIDEND, INTEREST, FEE,
TAX, SELL, SPLIT and WITHDRAWAL, with the same new symbol used by BUY,
DIVIDEND, SELL and SPLIT.

1. Analyze the statement and choose **Create** once for the unknown symbol.
   Expected: every compatible same-symbol/same-currency row resolves at once;
   only one instrument is planned.
2. Keep the earlier BUY included. Expected: the later SELL validates against
   that purchase and the later SPLIT validates against the remaining position.
3. Exclude the BUY. Expected: later SELL/SPLIT immediately become blocked;
   restoring the BUY replans them to their valid state.
4. Increase SELL above available quantity. Expected: oversell remains blocked.
5. Repeat with SELL listed earlier in the CSV but dated after BUY. Expected:
   date order, then source-row order, controls validation.
6. Map one row to an existing compatible instrument. Expected: the choice
   propagates only to the same normalized symbol and currency.
7. Commit. Expected: one instrument definition is created and every applicable
   activity uses it; no partial write occurs.
8. Re-import the exact source into the same account. Expected: zero duplicate
   transactions, instruments, transfers or other financial effects.

Record Windows and Android results separately. Do not infer either result from
automated engineering tests.
