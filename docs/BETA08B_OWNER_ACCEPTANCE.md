# BETA-08B Owner Acceptance

Use synthetic data only and confirm the household is healthy before testing.

## A — canonical CSV

Import this into a synthetic bank account:

```csv
date,description,amount,type,category,reference,note
2026-08-01,BETA CSV Grocery,250000,expense,BETA TEST Groceries,CSV001,CSV test
2026-08-02,BETA CSV Income,1500000,income,,CSV002,CSV test income
```

Verify preview counts/category/totals, import, ordinary sync, and receipt on the
second device. Re-import the exact file and verify zero new transactions and
zero new pending mutations.

## B — external bank CSV

Use a synthetic statement containing date, description, debit, credit, and
irrelevant columns. Map the columns, separators, and explicit date format.
Verify debit is expense, credit is income, and extra columns are ignored.

## C — semantic duplicate

Create an existing matching transaction with another ID. Verify the CSV row is
classified as a duplicate or possible duplicate and is excluded.

## D — review

Change one category and description, exclude one row, and import. Verify only
the reviewed included rows exist. Cancel a second review and verify no rows or
outbox operations are created.

## E — cross-device and offline

Verify the linked household stays linked, pending returns to zero, and another
device receives the imported rows. While offline, verify review is available,
the local-data freshness warning is shown, the local-first commit succeeds, and
normal sync resumes later.

Record device/build identities, counts, pending status, and any discrepancy.
Owner PASS is not claimed by the engineering checkpoint alone.
