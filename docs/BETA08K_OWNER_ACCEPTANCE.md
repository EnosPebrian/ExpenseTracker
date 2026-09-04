# BETA-08K Owner Acceptance

Status: **NOT RUN**

Run this later on the configured Windows and Android owner builds:

1. On Device A, open Health Check and confirm cloud-linked, Pending 0, no
   unresolved conflicts, and a successful sync time.
2. Add a transaction on Device A and wait for automatic sync (or use **Sync
   now**). Confirm Pending returns to 0.
3. Confirm Device B receives the transaction without closing/reopening.
4. Use a fresh test profile/device, sign in, and verify only authorized active
   household memberships appear.
5. If more than one household exists, select the intended household.
6. Download it and verify accounts, categories, transactions, budgets, rules,
   Import Inbox state, and canonical transfer links.
7. Confirm the original empty/local setup did not upload over the hosted data.
8. Put Device A offline, create a transaction, and confirm it is immediately
   visible locally with a waiting count.
9. Reconnect/foreground Pilgrim and confirm automatic sync returns Pending to
   0 and Device B receives the transaction.
10. Confirm no backup file and no original-device pairing was required.

Also verify the documented limitation: changes still showing Pending > 0 are
not recoverable on another device, and local-only households still depend on
encrypted backups for device-loss recovery.

