# BETA-08A engineering checkpoint

Milestone: Selective Backup Recovery & Shared Ingestion Foundation.

The implementation adds separate additive backup recovery without changing
replacement restore. It enforces same-household identity, read-only hosted
verification for linked books, stable-ID idempotency, conservative duplicate,
conflict, and tombstone classification, dependency planning, and one atomic
local mutation/outbox commit.

SQLite remains version 21. Backup format remains v2 with v1 compatibility. No
Supabase migration or RPC was added. Existing calculations, authoritative
reconnect, encryption, restore, and sync protocols remain unchanged.

Supported additive entities are accounts, categories, projects, asset
definitions, monthly budgets, and transactions. Household, members, and manual
market prices are preview-only. Member authority remains hosted-authoritative.

Engineering verification completed on 2026-08-09:

- `dart format` completed for the changed Dart files;
- `flutter analyze` passed with no issues;
- focused BETA-08A recovery tests passed: 18;
- full Flutter suite passed: 649;
- `flutter build web` passed;
- `flutter build windows --debug` passed;
- `flutter build apk --debug` passed, with the known forward-looking
  `file_picker` Kotlin compatibility warning.

Real Enos/Grace cross-device acceptance follows
`BETA08A_OWNER_ACCEPTANCE.md` and is not implied by automated checks.
