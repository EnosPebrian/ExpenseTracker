# Consolidated Owner Acceptance — BETA-08A1 through BETA-08H

Status: **NOT RUN — WAITING FOR HOSTED DEPLOYMENT**.

This checklist consolidates real Windows/Android integration boundaries. It
does not repeat automated edge-case matrices and must use synthetic or
non-sensitive sources wherever practical. Record observed results only; never
infer PASS from engineering tests.

## Preconditions

- BETA-08H1 Hosted Deployment PASS is recorded.
- Owner-ready Windows and owner-signed Android artifacts are installed without
  clearing existing app data.
- Both devices open the existing household, authenticate, converge to
  `Pending 0`, and load Integrations and Import Inbox.
- A designated test household and synthetic accounts/categories are available.

## Consolidated scenarios

| Scenario | Practical owner proof | Status |
| --- | --- | --- |
| A — Restore lifecycle | Restore entire backup; prove Keep local survives reopen, Reconnect Existing is download-authoritative, and Create New Shared Household uses a separate cloud identity. | NOT RUN |
| B — Selective recovery | BETA-08A is already owner PASS; run only a quick regression if Scenario A naturally exercises it. | ACCEPTED BASELINE |
| C — CSV, rules, Inbox, G1 | Import a tiny synthetic source, Save for later, reopen, review deterministic rule/manual precedence, select account, confirm canonical final identity, commit, and prove same-source/same-account reimport creates no duplicate finance. | NOT RUN |
| D — Receipt | Import a non-sensitive receipt, inspect/correct extraction, Save for later, and verify no automatic financial write. Commit is optional. | NOT RUN |
| E — Statement | Import an unlocked synthetic PDF/image statement, verify row normalization, summary exclusion, reconciliation, review, and no retained source file. | NOT RUN |
| F — Internal transfer | Match equal opposite synthetic legs across two accounts; confirm the canonical pair, reporting/budget/tithe exclusion, sync convergence, and optionally unpair once. | NOT RUN |
| G — Cross-device Inbox | Create pending review on one device; verify normalized drafts (not source bytes) on the second device, unresolved account persistence, edit sync, and safe account-dependent identity finalization. | NOT RUN |
| H — Telegram | In a private chat pair with a one-time token, send synthetic canonical CSV/receipt/statement, verify unresolved Inbox delivery and no direct finance, explicitly commit CSV in Pilgrim, prove duplicate protection, disconnect, then verify later attachments are rejected. | NOT RUN |

After every scenario that creates financial data, require `Synced`, `Pending 0`,
a recent success timestamp, and second-device convergence before continuing.
Use at most one meaningful cross-device conflict exercise; automated tests
remain authority for the exhaustive conflict matrix.

## Telegram live safety sequence

1. Generate a pairing token in Settings > Integrations > Telegram for the test
   household and send `/link <token>` in a private chat. Do not paste the token
   into Codex or logs.
2. Send a two-row synthetic canonical CSV. Before account selection, verify one
   Inbox session, two normalized drafts, populated source identity, null account,
   null final transaction IDs/bindings, and zero transactions/transfer links/
   financial outbox operations.
3. Verify the session reaches the second device through ordinary Inbox sync.
4. Select a synthetic account in Pilgrim and verify canonical G1 final IDs,
   account bindings, duplicate refresh, and transfer refresh before committing.
5. Explicitly commit and verify ordinary financial sync and second-device
   convergence.
6. Send the same bytes as a new message, select the same account, respect the
   duplicate warning, and verify zero additional financial rows.
7. Send one synthetic receipt and one synthetic unlocked statement; Inbox
   delivery is sufficient and neither needs to be committed.
8. Check minimal negatives: unsupported/noncanonical source rejected, arbitrary
   URL not fetched, group use not accepted, and post-disconnect attachment
   rejected.

## Verdict gate

Consolidated Owner Runtime PASS requires actual owner evidence for restore
lifecycle, CSV/rules, receipt, statement, canonical transfer, persistent
cross-device Inbox, deferred identity, Telegram ingestion, explicit ordinary
commit/sync, duplicate protection, and second-device convergence. Until those
observations are recorded, the verdict remains **NOT RUN**.
