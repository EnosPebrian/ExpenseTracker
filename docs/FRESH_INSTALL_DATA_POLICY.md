# Fresh-Install Data Policy

Production bootstrap loads existing records only. It must never create accounts,
projects, categories, transactions, balances, household activity, or sync activity.
The only automatic presets are reference asset definitions (gold, Bitcoin,
inventory, USD, and SGD). Currency support, tithe policy versions, and schema
metadata remain code/schema reference data rather than user financial records.

The former demo transactions and personalized account/category/project lists
were runtime Dart seeds, not SQLite migrations and not a packaged database.
Sample transactions now exist only in `test/support/demo_financial_fixture.dart`
and require an explicit test call. Files under `test/` are unreachable from a
release build.

Windows incremental builds can retain files created by an earlier run inside
the Release output directory. The Windows install step now removes only the
generated bundle's `.dart_tool` directory so a stale runtime database cannot be
packaged. The verified release contains no `.db`, `.sqlite`, or `.sqlite3` file
and none of the former demo strings.

No automatic cleanup migration is provided. Legacy demo transactions used
generated UUIDs, and seeded native accounts also used generated UUIDs. Names and
amounts are not safe ownership markers, so automatic removal could delete real
user records.

## Safely reset the current Windows demo database

1. Close Pilgrim Tracker completely.
2. In PowerShell, locate the exact database:

   ```powershell
   Get-ChildItem $env:USERPROFILE -Filter pilgrim_tracker.db -File -Recurse -ErrorAction SilentlyContinue
   ```

   The current Windows storage implementation normally places it under
   `.dart_tool\sqflite_common_ffi\databases` relative to the app's working
   directory.
3. Copy the located `pilgrim_tracker.db` somewhere safe as a backup.
4. Rename that exact file to `pilgrim_tracker.demo-backup.db`. Do not delete or
   rename any other `.db` file.
5. Install and launch the corrected release. It creates an empty database.
6. After verifying the empty dashboard, retain the backup until certain it
   contains no records that need manual re-entry.

This reset removes all local Pilgrim Tracker data in that database, not only the
demo rows. Do not use it on an installation containing real records unless the
backup has been verified.
