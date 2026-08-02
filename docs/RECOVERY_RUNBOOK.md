# Recovery Runbook

## Normal connected device change

1. Install Pilgrim Tracker on the new device.
2. Sign in with the authorized email identity.
3. Accept or select the existing household membership.
4. Download the shared household through Initial Synchronization.
5. Verify counts and dashboard totals before entering new activity.

A `.ptbackup` is not required for a normal synchronized device switch.

## Emergency or historical recovery

1. Open **Backup & Export** and select the `.ptbackup`.
2. Enter its password and choose **Validate and preview**.
3. Compare household name, date, versions, and counts.
4. Prefer **Restore as a new local household**.
5. Verify accounts, transactions, projects, assets, totals, fees, and deleted
   state while local-only.
6. Relink cloud sharing only after choosing which local/cloud history is
   authoritative. Never independently sync two divergent histories as a merge.

For matching-household replacement, save the required pre-restore safety
backup, type the exact household name, restore, verify locally, then perform a
deliberate cloud reconciliation. Cancelling the safety-backup save cancels the
restore before any database change.

## Owner/server protection

Hosted Supabase database backup protects the server project; it does not
replace per-household `.ptbackup`. CSV protects readability, and synchronization
is not historical backup. On plans without managed backup retention, the owner
should periodically run a linked, owner-controlled logical dump, for example:

```text
supabase db dump --linked --file <secure-owner-path>/pilgrim-YYYY-MM-DD.sql
```

Authenticate interactively or through the owner's secret manager. Never put a
database password, access token, or dump in a committed script/repository.
Encrypt the destination, restrict access, rotate retention, and periodically
test restoration in an isolated owner environment.
