# BETA-08N Windows and Android Owner Acceptance

**Status:** PENDING / NOT RUN
**Hosted schema:** DEPLOYED through `20260910054452`

Run this matrix only with disposable brokerage data after creating a current
encrypted backup. Use the same linked household on Windows and Android, with
both authorized members signed in. Record evidence without exposing account
numbers, credentials, or real financial details. Do not mark this document PASS
until every required row passes on real devices.

| # | Platform/setup | Exact action | Expected result | Result |
| ---: | --- | --- | --- | --- |
| 1 | Windows, linked household, disposable brokerage currency selected | Create a brokerage account, then open Investments and Accounts | Account is stored and displayed once; its currency is explicit; no ordinary transaction is created | [ ] PASS [ ] FAIL |
| 2 | Android after sync | Open the same household and brokerage account | The new account appears once with the same stable identity and currency | [ ] PASS [ ] FAIL |
| 3 | Windows, owned cash account funded | Record DEPOSIT from the owned account into brokerage cash | One canonical transfer is created; source falls and brokerage cash rises once; income, expense, return, budget, and Tithe Due do not change | [ ] PASS [ ] FAIL |
| 4 | Windows, brokerage cash available and existing instrument selected | Record BUY with quantity, price, and fee | Cash decreases once by purchase plus fee; quantity and weighted-average basis increase; no ordinary spending or Tithe effect | [ ] PASS [ ] FAIL |
| 5 | Windows, position with known basis | Record a partial SELL with fee and note/reference | Quantity falls, brokerage cash increases by net proceeds, and realized P&L uses Pilgrim's weighted-average basis exactly once | [ ] PASS [ ] FAIL |
| 6 | Windows, same position | Attempt to SELL more than the available quantity | Save is blocked with a clear oversell message; no transaction, holding, cash, or outbox mutation occurs | [ ] PASS [ ] FAIL |
| 7 | Android, synced brokerage account | Record DIVIDEND | Brokerage cash and investment income rise once; ordinary income, budget, and Tithe Due remain unchanged | [ ] PASS [ ] FAIL |
| 8 | Android, synced brokerage account | Record standalone FEE | Brokerage cash and investment performance fall once; ordinary household expenses/budgets remain unchanged | [ ] PASS [ ] FAIL |
| 9 | Android, synced brokerage account | Record TAX/withholding | Brokerage cash and net investment performance fall once; no tax-law calculation or ordinary-budget effect is inferred | [ ] PASS [ ] FAIL |
| 10 | Android, owned destination account available | Record WITHDRAWAL from brokerage to the owned account | One canonical transfer is created; balances move once; income, expense, return, budget, and Tithe Due do not change | [ ] PASS [ ] FAIL |
| 11 | Windows, whole-result position quantity | Record a supported stock split | Quantity and per-unit basis adjust consistently; total basis, cash, realized P&L, budget, and Tithe remain unchanged | [ ] PASS [ ] FAIL |
| 12 | Windows and Android after sync | Open Investments position detail | Both show identical quantity, remaining cost, average cost, current value when priced, and unrealized P&L; stale/missing prices remain explicit | [ ] PASS [ ] FAIL |
| 13 | Windows, note net worth before and after disposable brokerage funding/trade | Compare Overview/net-worth totals | Brokerage cash plus position value is included exactly once; the owned-account transfer is not double-counted | [ ] PASS [ ] FAIL |
| 14 | Windows, current monthly budget noted | Repeat BUY, SELL, DIVIDEND, FEE, TAX, DEPOSIT, and WITHDRAWAL checks | Ordinary category budget totals do not change from investment activity | [ ] PASS [ ] FAIL |
| 15 | Windows, Tithe Due/Paid noted | Repeat the investment activity checks | Tithe Due/Paid does not change automatically for principal, P&L, dividend, fee, tax, or funding | [ ] PASS [ ] FAIL |
| 16 | Windows, canonical UTF-8 brokerage CSV with all eight supported activities | Select Import statement, map columns, review every row, and commit | Explicit preview is shown; approved rows post atomically with correct cash/position/transfer effects | [ ] PASS [ ] FAIL |
| 17 | Windows, CSV containing an unknown activity value | Include the row and try to commit, then choose an explicit supported activity | `UNRESOLVED` blocks commit; no guess occurs; commit becomes available only after explicit resolution | [ ] PASS [ ] FAIL |
| 18 | Windows, CSV containing an unknown symbol | Review the row, test Map to existing, then separately test Create compatible asset with disposable data | No instrument is silently created; each explicit choice is visible and uses a stable compatible definition | [ ] PASS [ ] FAIL |
| 19 | Windows, completed imported statement | Import the exact same file into the same brokerage account again | Duplicate review identifies the rows; commit adds zero financial rows and zero pending outbox operations | [ ] PASS [ ] FAIL |
| 20 | Android offline, reference data already local | Record one valid manual brokerage activity and close/reopen the app | Activity, position, cash, note/reference, and pending sync survive restart without network | [ ] PASS [ ] FAIL |
| 21 | Windows offline, mapped CSV and reference data local | Import and commit a small valid statement | Review and atomic local commit succeed; rows remain queued once for ordinary sync | [ ] PASS [ ] FAIL |
| 22 | Restore connectivity on both devices | Trigger Sync now, then open Investments on the other device | Manual and imported activities converge once with matching metadata, cash, positions, and no echo duplicate | [ ] PASS [ ] FAIL |
| 23 | Clean/new authorized device with no local financial data | Sign in, select the hosted household, and complete initial download | Brokerage account attribution, activities, transfer links, notes/references, positions, and balances bootstrap correctly | [ ] PASS [ ] FAIL |
| 24 | Windows, current household with disposable brokerage history | Create/validate encrypted v7 backup, restore it exactly, and inspect Investments | Restore completes without duplicates; account/instrument references, activities, positions, cash, notes, and references match | [ ] PASS [ ] FAIL |
| 25 | Android after synchronized state is current | Force-close and reopen Pilgrim Tracker | Session, selected household, brokerage accounts, imported/manual history, positions, values, and synchronization state persist | [ ] PASS [ ] FAIL |

## Final owner verdict

- Windows required checks: [ ] PASS [ ] FAIL
- Android required checks: [ ] PASS [ ] FAIL
- Cross-device synchronization/bootstrap: [ ] PASS [ ] FAIL
- Backup/restore: [ ] PASS [ ] FAIL
- Owner acceptance date: ____________________
- Owner notes: ______________________________

Until the owner completes and records this matrix, BETA-08N owner acceptance
remains **PENDING / NOT RUN**.
