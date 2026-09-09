# BETA-08M Owner Acceptance

**Status:** NOT RUN

Run this later on the approved Windows and Android builds with a disposable CSV
and household backup:

1. Import rows containing an exact known category and confirm automatic exact
   mapping.
2. Import repeated unknown categories and verify the rows remain reviewable.
3. Map the unknown value to an existing category, manually override one row,
   and verify the row override remains unchanged.
4. Choose Create, cancel or discard, and verify no category was created.
5. Choose Create, Save for later, restart, and verify the intent returns while
   no category exists.
6. Commit and verify exactly one category and the selected transactions appear.
7. Choose Ignore and verify the committed transaction is uncategorized.
8. Reimport the same source/account and verify no duplicate transaction or
   category is created.
9. While linked but offline, commit a Create import, reconnect, and verify a
   second authorized device receives one category and its transactions.
10. Back up and restore the committed household and verify both category and
    transactions remain linked.
11. Verify `Tithe`, `tithe`, and spaced variants use the protected System Tithe
    category without changing a same-name custom category.

Do not mark owner acceptance PASS until these runtime checks are completed.
