# BETA-07C2 Owner Reproduction

Use this check only with the existing **Enos & Grace Beta Test** household. Windows is the authoritative device for this recovery.

## Before starting

- On Windows, confirm the household is **Synced**, **Pending: 0**, and has a current **Last successful** time.
- Leave the Windows data unchanged while Android reconnects.
- On Android, sign in as Grace and confirm the active hosted membership is visible.

## Reconnect the restored Android household

1. Restore the encrypted backup on Android using replacement restore.
2. Close Android completely and reopen it.
3. Open **Household**.
4. While remote membership and manifest data load, expect **Checking cloud household…**. The page must not briefly show **Initial upload required**.
5. For the matching initialized household, expect **Reconnect cloud sharing**. The guidance must state that hosted data is authoritative and that local-only restored changes will not be merged or uploaded.
6. Select **Enos & Grace Beta Test** if a selection is shown.
7. Continue only after the encrypted safety backup succeeds.
8. Start the hosted download and wait for validation and atomic replacement to complete.
9. Expect **Synced**, **Pending: 0**, and a current **Last successful** time.
10. Close Android completely, reopen it, and revisit **Household**. It must still show the same synced state; it must not return to initial upload or reconnect.

## Cross-device confirmation

1. On Android, create one clearly named disposable transaction.
2. Confirm Android returns to **Synced** with **Pending: 0**.
3. On Windows, synchronize if needed and confirm the transaction appears without restarting the app.
4. Delete the disposable transaction only through the normal application workflow if cleanup is wanted.

## Expected evidence

Capture these states if reporting a failure:

- Windows before reconnect: **Synced / Pending: 0 / current Last successful**.
- Android after restart: **Reconnect cloud sharing**, not **Initial upload required**.
- Android during reconnect: successful encrypted safety backup followed by hosted download.
- Android after completion and after a second restart: **Synced / Pending: 0 / current Last successful**.
- Windows after the disposable Android transaction: the same transaction is present.

Do not use primary upload for this scenario. Do not merge or upload the restored Android snapshot; the initialized hosted household is authoritative.
