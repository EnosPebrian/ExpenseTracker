# BETA-08A owner acceptance

Expected start: Windows and Android are Synced, Pending 0, and the old Android
backup contains unique historical transactions absent from hosted state.

1. Create a fresh current safety backup first.
2. Open Backup & Export.
3. Select Recover from backup.
4. Select the OLD Android `.ptbackup`.
5. Enter password.
6. Analyze.
7. Verify household matches.
8. Verify unique historical transactions appear as Recoverable.
9. Verify current/cloud transactions appear Already present.
10. Verify no current record is proposed for deletion.
11. Select the unique historical transactions.
12. Review dependencies.
13. Recover selected.
14. Verify Android remains: Synced.
15. Pending should temporarily increase if normal outbox mutations exist.
16. Wait for Pending 0.
17. Verify recovered transactions appear on Windows.
18. Close/reopen both apps.
19. Verify both remain Synced.
20. Run Recover from backup against the SAME file again.
21. Verify zero additional transactions are proposed/imported.

Record device/build identities, candidate and dependency counts, the pending
transition, cross-device result, and repeated-run result with screenshots.
