# BETA-08N Windows and Android Owner Acceptance

**Status:** PARTIAL — targeted 125-row RDN regression PASS; remaining matrix
DEFERRED BY OWNER / NOT EXECUTED
**Hosted schema:** DEPLOYED through `20260921144802`
**Feature freeze:** ACTIVE

## Targeted 125-row RDN regression acceptance — PASS

Owner acceptance was completed on Windows with the real 125-row Stockbit/RDN
CSV. Observed result:

- Invalid: 0;
- Unresolved: 0;
- 71 fractional-IDR values entered the accepted HALF_UP review path;
- one session-level rounding approval was available;
- original fractional source values were visible as provenance;
- BUY_SETTLEMENT and SELL_SETTLEMENT imported as zero-financial-effect
  settlement evidence;
- Interest was recognized as Interest without requiring an instrument;
- import completed for 86 selected events;
- 16 financial rows were created;
- 0 instruments were created;
- 39 rows remained duplicate/review candidates and were not blindly imported.

The 39 duplicate/review candidates are expected review-policy outcomes, not an
import failure. This targeted acceptance closes the original fractional-IDR and
stale-runtime blocker.

The owner intentionally deferred every unexecuted Windows, Android,
cross-device, bootstrap, backup/restore and restart check below. Their status is
**DEFERRED BY OWNER / NOT EXECUTED**, not PASS.

## Full Interest repair matrix — DEFERRED BY OWNER / NOT EXECUTED

The Interest migration and settlement ACL hardening are deployed. Use a current
encrypted backup before beginning owner testing.

| Setup | Action | Expected result | Result |
| --- | --- | --- | --- |
| Windows, disposable IDR brokerage/RDN account | Record positive INTEREST 10,000 without an instrument | Brokerage cash and Interest Income rise 10,000 once; Dividend, position, basis, realized/unrealized trade P&L, ordinary income/expense, budget, Project and Tithe Due/Paid do not change | [ ] PASS [ ] FAIL |
| Same setup | Record explicit TAX 2,000 after the Interest | Brokerage cash net is +8,000; Interest Income remains 10,000; Fees/Tax reports 2,000 | [ ] PASS [ ] FAIL |
| Brokerage CSV with exact INTEREST, blank symbol/quantity/price | Analyze and import | Row is Ready without instrument mapping and commits once | [ ] PASS [ ] FAIL |
| Same CSV/account | Reimport exactly | Already present; zero new financial rows or outbox operations | [ ] PASS [ ] FAIL |
| CSV with INTEREST 0 and -10,000 | Analyze and try to commit | Both preserve source values and block; neither becomes positive, Dividend, or Fee | [ ] PASS [ ] FAIL |
| Windows offline then Android after reconnect | Record/import Interest, close/reopen, sync and inspect second device | Stable Interest activity persists and converges once with no instrument or duplicate | [ ] PASS [ ] FAIL |
| Current encrypted v8 backup | Backup, restore and clone disposable Interest history | Interest identity, amount, note/reference and account attribution survive; no duplicate effect | [ ] PASS [ ] FAIL |

## Full Settlement repair matrix — DEFERRED BY OWNER / NOT EXECUTED

The settlement migration and least-privilege ACL correction are deployed.

The real RDN CSV acceptance must explicitly verify:

- `BUY_SETTLEMENT` and `SELL_SETTLEMENT` auto-resolve without Buy/Sell selection
  or an instrument, persist as settlement evidence, and have zero financial
  effect.
- `INTEREST` auto-resolves without an instrument, increases brokerage cash and
  Interest Income once, and does not affect ordinary income, budgets, Projects,
  or Tithe.
- `DIVIDEND` remains distinct, exact existing symbols auto-map, and an unknown
  symbol requires one explicit Map/Create decision without repetitive per-row
  resolution once statement-level staging resolves that symbol.
- DEPOSIT, WITHDRAWAL, FEE and TAX retain their accepted semantics.
- Exact re-import creates zero duplicate financial, settlement, or Interest
  effects.

| Setup | Action | Expected result | Result |
| --- | --- | --- | --- |
| Windows, disposable RDN CSV with BUY_SETTLEMENT and SELL_SETTLEMENT | Analyze and import with no instrument or matching trade | Ready unmatched evidence; no “choose Buy/Sell” error; no financial totals change | [ ] PASS [ ] FAIL |
| Same file/account | Reimport exact CSV | Already present; zero extra evidence, transactions or sync mutations | [ ] PASS [ ] FAIL |
| Evidence plus compatible BUY/SELL trades | Open Settlement evidence; review one-to-many and many-to-one links explicitly | Reconciled state; original trade IDs/values and all totals unchanged | [ ] PASS [ ] FAIL |
| Several compatible candidates | Open review without confirming | Suggestions do not auto-confirm; unmatched remains valid | [ ] PASS [ ] FAIL |
| Windows/Android offline | Import, close/reopen, then reconnect after authorized schema rollout | Evidence persists and syncs without duplicate financial effect | [ ] PASS [ ] FAIL |
| Current encrypted backup | Backup, restore and clone | Evidence/source fields retained; clone account/trade links remapped | [ ] PASS [ ] FAIL |

Run this matrix only with disposable brokerage data after creating a current
encrypted backup. Use the same linked household on Windows and Android, with
both authorized members signed in. Record evidence without exposing account
numbers, credentials, or real financial details. Do not mark the full BETA-08N
owner matrix PASS until every required row is actually executed on real devices.

| # | Platform/setup | Exact action | Expected result | Result |
| ---: | --- | --- | --- | --- |
| 1 | Windows, linked household, disposable brokerage currency selected | Create a brokerage account, then open Investments and Accounts | Account is stored and displayed once; its currency is explicit; no ordinary transaction is created | [ ] PASS [ ] FAIL |
| 2 | Android after sync | Open the same household and brokerage account | The new account appears once with the same stable identity and currency | [ ] PASS [ ] FAIL |
| 3 | Windows, owned cash account funded | Record DEPOSIT from the owned account into brokerage cash | One canonical transfer is created; source falls and brokerage cash rises once; income, expense, return, budget, and Tithe Due do not change | [ ] PASS [ ] FAIL |
| 4 | Windows, brokerage cash available and existing instrument selected | Record BUY with quantity, price, and fee | Cash decreases once by purchase plus fee; quantity and weighted-average basis increase; no ordinary spending or Tithe effect | [ ] PASS [ ] FAIL |
| 5 | Windows, position with known basis | Record a partial SELL with fee and note/reference | Quantity falls, brokerage cash increases by net proceeds, and realized P&L uses Pilgrim's weighted-average basis exactly once | [ ] PASS [ ] FAIL |
| 6 | Windows, same position | Attempt to SELL more than the available quantity | Save is blocked with a clear oversell message; no transaction, holding, cash, or outbox mutation occurs | [ ] PASS [ ] FAIL |
| 7 | Android, synced brokerage account | Record DIVIDEND | Brokerage cash and Dividend Income rise once; Interest Income, ordinary income, budget, and Tithe Due remain unchanged | [ ] PASS [ ] FAIL |
| 8 | Android, synced brokerage account | Record standalone FEE | Brokerage cash and investment performance fall once; ordinary household expenses/budgets remain unchanged | [ ] PASS [ ] FAIL |
| 9 | Android, synced brokerage account | Record TAX/withholding | Brokerage cash and net investment performance fall once; no tax-law calculation or ordinary-budget effect is inferred | [ ] PASS [ ] FAIL |
| 10 | Android, owned destination account available | Record WITHDRAWAL from brokerage to the owned account | One canonical transfer is created; balances move once; income, expense, return, budget, and Tithe Due do not change | [ ] PASS [ ] FAIL |
| 11 | Windows, whole-result position quantity | Record a supported stock split | Quantity and per-unit basis adjust consistently; total basis, cash, realized P&L, budget, and Tithe remain unchanged | [ ] PASS [ ] FAIL |
| 12 | Windows and Android after sync | Open Investments position detail | Both show identical quantity, remaining cost, average cost, current value when priced, and unrealized P&L; stale/missing prices remain explicit | [ ] PASS [ ] FAIL |
| 13 | Windows, note net worth before and after disposable brokerage funding/trade | Compare Overview/net-worth totals | Brokerage cash plus position value is included exactly once; the owned-account transfer is not double-counted | [ ] PASS [ ] FAIL |
| 14 | Windows, current monthly budget noted | Repeat BUY, SELL, DIVIDEND, FEE, TAX, DEPOSIT, and WITHDRAWAL checks | Ordinary category budget totals do not change from investment activity | [ ] PASS [ ] FAIL |
| 15 | Windows, Tithe Due/Paid noted | Repeat the investment activity checks | Tithe Due/Paid does not change automatically for principal, P&L, dividend, fee, tax, or funding | [ ] PASS [ ] FAIL |
| 16 | Windows, canonical UTF-8 brokerage CSV with all nine supported activities | Select Import statement, map columns, review every row, and commit | Explicit preview is shown; approved rows post atomically with correct cash/position/transfer effects | [ ] PASS [ ] FAIL |
| 17 | Windows, CSV containing an unknown activity value | Include the row and try to commit, then choose an explicit supported activity | `UNRESOLVED` blocks commit; no guess occurs; commit becomes available only after explicit resolution | [ ] PASS [ ] FAIL |
| 18 | Windows, CSV containing an unknown symbol | Review the row, test Map to existing, then separately test Create compatible asset with disposable data | No instrument is silently created; each explicit choice is visible and uses a stable compatible definition | [ ] PASS [ ] FAIL |
| 19 | Windows, completed imported statement | Import the exact same file into the same brokerage account again | Duplicate review identifies the rows; commit adds zero financial rows and zero pending outbox operations | [ ] PASS [ ] FAIL |
| 20 | Android offline, reference data already local | Record one valid manual brokerage activity and close/reopen the app | Activity, position, cash, note/reference, and pending sync survive restart without network | [ ] PASS [ ] FAIL |
| 21 | Windows offline, mapped CSV and reference data local | Import and commit a small valid statement | Review and atomic local commit succeed; rows remain queued once for ordinary sync | [ ] PASS [ ] FAIL |
| 22 | Restore connectivity on both devices | Trigger Sync now, then open Investments on the other device | Manual and imported activities converge once with matching metadata, cash, positions, and no echo duplicate | [ ] PASS [ ] FAIL |
| 23 | Clean/new authorized device with no local financial data | Sign in, select the hosted household, and complete initial download | Brokerage account attribution, activities, transfer links, notes/references, positions, and balances bootstrap correctly | [ ] PASS [ ] FAIL |
| 24 | Windows, current household with disposable brokerage history | Create/validate encrypted v8 backup, restore it exactly, and inspect Investments | Restore completes without duplicates; account/instrument references, activities, positions, cash, notes, and references match | [ ] PASS [ ] FAIL |
| 25 | Android after synchronized state is current | Force-close and reopen Pilgrim Tracker | Session, selected household, brokerage accounts, imported/manual history, positions, values, and synchronization state persist | [ ] PASS [ ] FAIL |

## Final owner verdict

- Targeted 125-row Windows RDN regression: [x] PASS [ ] FAIL
- Remaining Windows required checks: DEFERRED BY OWNER / NOT EXECUTED
- Android required checks: DEFERRED BY OWNER / NOT EXECUTED
- Cross-device synchronization/bootstrap: DEFERRED BY OWNER / NOT EXECUTED
- Backup/restore: DEFERRED BY OWNER / NOT EXECUTED
- Targeted acceptance date: 2026-09-23
- Owner notes: 39 duplicate/review candidates remain governed by existing
  duplicate-review policy and are not an import failure.

The targeted RDN regression is accepted. Full BETA-08N owner acceptance remains
incomplete because the remainder was **DEFERRED BY OWNER / NOT EXECUTED**.
