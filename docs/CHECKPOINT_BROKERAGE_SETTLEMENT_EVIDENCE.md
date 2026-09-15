# Brokerage Settlement Evidence — 2026-09-15

PT-BETA-08N1-R3 automated engineering verification PASS. Git finalization pending.

- Settlement rows are durable reconciliation evidence, never financial postings.
- Reviewed links support many-to-many cardinality. Suggestions never auto-confirm.
- Source metadata and underlying trade identity remain unchanged.
- Native/web atomic persistence, restart, remote apply, backup/clone/recovery
  integration use SQLite 29 and encrypted backup v8.
- One new local migration: 20260915004307_brokerage_settlement_evidence.sql.
- Focused Flutter: 33/33. Full Flutter: 1010/1010. Analyzer: clean.
- Web, Windows debug, Android debug APK: PASS; existing file_picker warning.
- Local clean replay: PASS. pgTAP: 12/12 focused, 326/326 full.
- Local security advisor: no errors; two unchanged legacy search-path warnings.
- Hosted deployment: NOT RUN. Physical-device owner acceptance: NOT RUN.

Limitations: Interest is a separate unimplemented activity; suggestions rank
reference/gross amount and a seven-day window without inferred allocations.
Hosted settlement sync requires separately authorized deployment of the new
migration. Do not deploy this migration under the current work item.
