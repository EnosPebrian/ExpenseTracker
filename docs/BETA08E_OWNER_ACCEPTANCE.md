# BETA-08E owner acceptance

Status: **NOT RUN — intentionally deferred**.

This does not change the deferred owner runtime status of BETA-08A1, BETA-08B,
BETA-08C, or BETA-08D.

## Future owner scenarios

1. Create an expense rule: description contains `PERTAMINA` → Fuel.
2. Import a CSV row containing Pertamina and confirm Fuel is suggested.
3. Import a Pertamina receipt and confirm the same suggestion.
4. Import a statement row containing Pertamina and confirm the same suggestion.
5. Override one draft and confirm the manual category wins.
6. Disable the rule and confirm later drafts receive no suggestion.
7. Edit the rule on Windows and confirm Android receives it through sync.
8. Import on Android and confirm the edited rule applies.
9. Re-import the exact source and confirm zero duplicate transactions.

Acceptance must also inspect ambiguity wording, unavailable-category behavior,
narrow Android layout, Windows layout, and encrypted backup v3 restore/recovery.
