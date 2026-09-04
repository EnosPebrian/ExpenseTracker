# BETA-08I Owner Acceptance

Status: **NOT RUN**

Engineering fixtures are not a substitute for owner runtime acceptance. After
engineering verification closes, test with representative private household
data on Windows and Android:

1. Generate a Monthly Household statement.
2. Compare its income and expense totals with Reports for the same month.
3. Confirm a canonical internal transfer does not inflate household totals.
4. Generate a Monthly Account statement and verify opening, running, and
   closing balances against the account activity.
5. Export and open the PDF on Windows using a user-selected destination.
6. Export and open the PDF on Android using the existing document workflow.
7. Generate an Annual Household and an Annual Account statement.
8. If multiple currencies exist, verify each is presented separately.
9. With linked pending changes, verify the local-data warning appears.

Acceptance must record device/build, selected period/scope, expected versus
observed totals, exported filename, and whether the PDF opened correctly.

