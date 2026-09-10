# BETA-08N1 Owner Acceptance

**Status:** NOT RUN

Run later on approved Windows and Android builds with disposable broker data
and a current encrypted backup:

1. Import a canonical UTF-8 brokerage CSV containing all eight supported
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
