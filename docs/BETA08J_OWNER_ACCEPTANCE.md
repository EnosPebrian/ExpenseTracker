# BETA-08J Owner Acceptance

**Status: NOT RUN**

Owner/runtime acceptance is intentionally deferred until BETA-08H1 hosted
deployment and consolidated acceptance can resume.

## Future Windows and Android scenario

1. Open **Data & Sync → Health Check** on Windows and Android.
2. Run Health Check on ordinary local data and confirm there is no false
   critical result.
3. Save an ordinary import for later; confirm the pending Inbox count is
   informational and overall may remain Healthy.
4. With a linked household offline or hosted cloud unavailable, confirm local
   data sections remain independently healthy while Sync requests attention.
5. Restore connectivity and complete normal explicit synchronization; run
   again and confirm pending changes return to zero.
6. Copy the diagnostic summary and verify it contains operational status only,
   with no amounts, descriptions, account numbers, raw IDs, fingerprints, or
   secrets.
7. Run Health Check before and after the consolidated BETA-08A1 through
   BETA-08J owner scenarios.

Health Check must never initiate synchronization or repair data during these
steps.
