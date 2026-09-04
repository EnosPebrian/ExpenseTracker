# BETA-08F1 Owner Acceptance

Status: **NOT RUN**.

Use a controlled Windows/Android household with backups made before testing.

1. Import an outgoing `TRANSFER TO GRACE` IDR 5,000,000 row into BCA Enos and commit it normally.
2. In a later import session, import the equal incoming `TRANSFER FROM ENOS` row into BCA Grace. Confirm the proposed internal transfer.
3. Verify one logical transfer, unchanged -5,000,000/+5,000,000 account movement, and exclusion from household expense, income, budget, and tithe totals.
4. Re-import the same source and verify no duplicate transaction, link, or outbox mutation.
5. Verify a one-day posting difference is `possible`.
6. Create equal-quality counterpart choices and verify `ambiguous` requires manual selection.
7. Unpair and verify ordinary expense/income classifications return.
8. Verify Windows and Android converge through the existing sync pipeline, including an offline confirmation followed by reconnect.

Do not mark BETA-08F1 or the consolidated BETA-08F owner gate accepted until these checks are completed by the owner.
