# BETA-01 Complete — Structured Accounts, Opening Balances, and Local Profile

## Verdict

BETA-01 is implemented. D14 is intentionally still open.

## Delivered

- Stable `Account` UUID records with account type, currency, signed integer
  opening amount, nullable effective date, and existing lifecycle/sync metadata.
- Compatibility getters expose both structured account records and account-name
  strings; transactions and existing entry forms remain name-based.
- Opening amounts live only on account rows. A null date is unset; zero with a
  date is configured. Transactions on the effective local date are included,
  earlier entries remain visible but are excluded from the account balance.
- Pure cash-effect calculation covers income, expense, buys/sells, capitalized
  and deducted fees, linked separate-fee expenses, deletion, and execution
  metadata. Ambiguous legacy transfers return zero.
- Accounts UI uses persisted records and calculated balances, supports
  create/edit/remove starting positions, accepts zero/negative values, retains
  drafts after validation errors, warns about earlier transactions, and adapts
  to narrow layouts.
- Device-local profile collects display name and default currency, persists the
  active session natively, and has in-memory web parity. It is not secure
  authentication.

## Persistence

SQLite is version 11. Fresh creation includes the three new account columns and
minimal `local_profiles` / `local_session` tables. Upgrade from version 10 (and
all historical paths) preserves existing financial rows, defaults accounts to
IDR/zero/unset, and creates a safe existing-user local profile. Transactions are
not rewritten.

## Reporting isolation

Opening balances are not transactions and do not change income, expenses, net
cash flow, activity, category/project reporting, tithe, asset quantities, cost
basis, or realized/unrealized gains.

## Verification

- Focused BETA-01 tests: 29 passed.
- Historical migration/reopen regression tests: passed after version-11 update.
- Full suite: 431 passed.
- Flutter analyzer: no issues.
- Web build: succeeded, including the WebAssembly dry run.

## D14 release work still pending

- Configure and securely retain the owner Android upload keystore and untracked
  `android/key.properties`.
- Rebuild and verify owner-signed APK/AAB artifacts.
- Run Android release runtime checks and fresh-data close/reopen verification on
  a physical device or configured emulator.
- Run the final branded Windows release build, interactive checklist, and
  fresh-data close/reopen verification.
- Complete any remaining closed-beta checklist gates and only then mark D14
  complete.
