# Cloud Durability and New-Device Bootstrap

## BETA-08M0 transaction metadata continuity

Notes and references save locally first and use the ordinary transaction
outbox. Initial upload/download and incremental pull preserve modern values;
legacy omitted update properties preserve existing values, while explicit null
clears them. A fresh device applies downloaded metadata without an outbox echo.
Null metadata is valid and is never treated as corruption.

## BETA-08L System Tithe convergence

Bootstrap ensures the deterministic System Tithe category after selecting the
active household and before master-data loading. Local-only households require
no login. In linked households a missing row follows ordinary category
persistence/outbox sync; a fresh device that already downloaded it performs a
no-op ensure with no duplicate outbox. Payments are ordinary transactions, so
offline save, reconnect, cursor pull, conflict behavior, and new-device history
use BETA-08K unchanged. Summaries recompute from the refreshed controller
snapshot; there is no Tithe-specific sync protocol.

## BETA-08L0 category continuity

Initial upload/download and transaction snapshots now retain nullable category
identity. New-device activation validates same-household category references and
does not enqueue downloaded records. Legacy nulls remain valid. The prerequisite
hosted migration is not deployed by this milestone; see
`TRANSACTION_CATEGORY_IDENTITY.md`.

## Storage model

Pilgrim remains local-first. Each native device owns an immediately writable
SQLite working replica. For a linked household, Supabase is the durable shared
record copy and the existing outbox/change-feed protocol converges devices.
Pilgrim never uploads a SQLite database as canonical data, downloads a `.db`
file for normal synchronization, or uses Drive/Dropbox file locking as sync.

Ordinary mutations commit locally with a durable outbox operation. Cloud
unavailability never blocks transaction entry. Sync runs while the application
can run and is requested after startup, foreground resume, local mutation,
manual **Sync now**, Realtime wake-up, and successful link/bootstrap. The
coordinator is single-flight; the controller debounces bursts and coalesces a
request received during an active run into one follow-up run. Retry remains
bounded by the existing backoff policy. There is no polling or OS background
service.

## New-device flow

After authentication, Pilgrim reads only active memberships visible to the
signed-in user through existing RLS. An unlinked device can inspect the
authorized stable manifests, choose among all initialized hosted households,
and select **Download shared household**. No household is enumerated without
membership.

The existing initial-sync protocol then:

1. captures an authorized remote snapshot at a server sequence;
2. downloads bounded entity batches to durable staging;
3. validates counts, household scope, identities, values, and references;
4. activates the complete household in one SQLite transaction;
5. preserves the remote member identity while the device keeps its own device
   identity; and
6. starts normal cursor synchronization to close the snapshot race.

Progress is stage/count based, never a fabricated percentage. An interruption
leaves the previous active household usable and resumes from durable staging.
Repeated batches and activation use stable IDs and do not duplicate records or
outbox work.

## Safety boundaries

- An empty new device downloads an initialized hosted household. It never
  offers the empty local book as an upload over that household.
- A populated target with the hosted household ID is rejected. Independent
  local history is never silently merged, uploaded, deleted, or overwritten.
- Restore reconnect remains a separate explicit operation: encrypted safety
  backup first, then authoritative staged download.
- Initial upload is available only for the matching linked local household, an
  active owner membership, an uninitialized/empty remote, and explicit owner
  confirmation.
- Revoked, absent, or foreign memberships cannot inspect or download a
  household through the client protocol.

## Recoverability and status

**Synced / Pending 0** means the currently synchronized household state is in
the shared cloud copy and can bootstrap another authorized device without the
original device. **N changes waiting** means those changes still exist only on
this device and cannot be recovered elsewhere until synchronization succeeds.
Conflict, failed, signed-out, and offline states say that sync needs attention;
they do not imply local database corruption.

Local-only households remain fully supported and require no authentication.
Device loss can lose a local-only household unless a valid encrypted backup
exists. Encrypted backups remain essential for disaster recovery, archival
snapshots, offline recovery, and catastrophic cloud/account recovery; they are
not the normal linked-household device-migration path.

Pilgrim does not promise continuous background synchronization while Android
or Windows has suspended or killed the process. Pending changes retry when the
application next starts or becomes active and connectivity is available.
