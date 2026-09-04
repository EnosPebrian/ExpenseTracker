# Financial Statements

Pilgrim generates financial statements on demand from the local household
database. Statements are derived exports: they are not stored, synchronized,
or added to encrypted backup payloads.

## Available statements

- Monthly Household: opening and closing balances by currency, income,
  expenses, net cash flow, tithe, transfer totals, account/category summaries,
  budget-versus-actual, and a transaction ledger.
- Annual Household: January 1 opening and year-end closing balances, annual
  totals, January-December summaries (including inactive months), category
  aggregation and monthly averages, account summaries, and budget/tithe data.
- Monthly Account: the selected account's native currency, opening balance,
  inflow, outflow, transfers, running balance, and closing balance.
- Annual Account: the same account reconciliation over a calendar year. Very
  large annual account ledgers are summarized by month in PDF; monthly
  statements provide complete transaction-level detail.

Periods use local calendar boundaries. Opening balance is the account balance
immediately before the period start; closing balance includes all
balance-affecting movements before the exclusive period end. Account rows are
ordered by transaction date, creation time, and stable record identity so the
running balance is deterministic.

## Financial classification

- Canonical internal-transfer legs remain visible as account movements but are
  excluded from household income, expenses, budget spending, and tithe income.
- Legacy single-row transfers remain visible under the established legacy
  policy. Pilgrim does not invent a direction or migrate them while exporting.
- Budget actuals use the existing monthly budget calculator.
- Tithe uses the existing policy and period calculation.
- Asset conversions use their existing cash effect and are not ordinary
  household income or expense.
- Deleted records are excluded. Historical transaction category/account
  snapshots continue to label archived history where available.

## Currencies and valuation

Household summaries are separated by currency. IDR, USD, SGD, or other natural
currencies are never silently summed. Account statements use the selected
account's native currency.

Pilgrim does not currently have reliable historical as-of market valuation for
all assets and liabilities. Annual statements therefore omit year-end net
worth and explicitly explain that omission rather than showing a current value
as if it were historical.

## Preview and PDF export

Reports > Financial Statements provides Monthly/Annual and Household/Account
selection, Generate, an on-screen preview, and Export PDF. The preview caps a
large ledger for responsive rendering; the statement model retains all rows.
PDFs are generated locally with the `pdf` package on A4 pages. They include
the statement title, period, scope, currencies, summary tables, page numbers,
and a detailed or explicitly summarized ledger. They never include internal
UUIDs, device IDs, sync metadata, or source fingerprints.

The existing portable-file abstraction provides the user-selected save flow on
Windows, the project-standard document picker/save flow on Android, and browser
download behavior on web. Paths are not hardcoded. Generated filenames are
sanitized and include statement type, period, and account name when applicable.

## Local-first and linked households

Generation and PDF rendering require no network call. When a linked household
has pending or incomplete local synchronization, the statement warns that it
reflects the records currently available on this device. Pilgrim does not
silently claim that such a statement is a complete cloud snapshot.

