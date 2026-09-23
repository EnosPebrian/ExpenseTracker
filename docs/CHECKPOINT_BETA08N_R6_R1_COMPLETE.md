# PT-BETA-08N-R6-R1 Complete

**Date:** 2026-09-23

**Verdict:** Engineering PASS; owner acceptance PENDING / NOT RUN

**Feature freeze:** ACTIVE

## Runtime diagnosis

The owner-reported `42563.75 IDR` failure was reproduced only in an obsolete
Windows Release artifact. The running application used:

```text
D:\ExpenseTracker\build\windows\x64\runner\Release\pilgrim_tracker.exe
```

Its compiled Dart payload, `Release\data\app.so`, was built on 2026-09-16.
The accepted R6 implementation was committed on 2026-09-22. The old payload
therefore still routed fractional IDR through generic zero-decimal parsing.

Current source routes IDR brokerage money fields through
`BrokerageIdrRoundingParser` before generic `CsvMoneyParser` precision checks.
No additional production repair, schema, Supabase or backup change was needed.

## Regression proof

A synthetic fixture mirrors all 14 columns and verified mappings from the real
RDN CSV without retaining owner financial data. The planner is injected with a
generic money parser that always throws. The regression proves:

- `BUY_SETTLEMENT` is recognized without an instrument;
- `42563.75 IDR` parses successfully and rounds HALF_UP to `42564`;
- exact source `42563.75` remains in durable provenance;
- the row requires session-level rounding approval;
- neither excessive-precision nor false positive-gross errors are emitted;
- after approval, settlement evidence stores `42564`;
- settlement import creates no financial transaction.

Existing focused tests continue to cover `30846.21 -> 30846`,
`42563.50 -> 42564`, `-42563.50 -> -42564`, Interest sign validation,
re-import identity and zero-effect settlements.

## Verification

```text
focused brokerage/settlement/Interest/duplicate/non-brokerage CSV: 84/84 PASS
flutter analyze: PASS
full Flutter suite: 1020/1020 PASS
flutter build web: PASS
flutter build windows --debug: PASS
flutter build apk --debug: PASS
git diff --check: PASS
known warning: unchanged file_picker forward-looking Kotlin warning
```

Current artifacts:

```text
build\windows\x64\runner\Debug\pilgrim_tracker.exe
build\app\outputs\flutter-apk\app-debug.apk
```

## Owner acceptance

PENDING / NOT RUN. Close the stale Release process, run a current artifact,
reanalyze the real 125-row CSV, approve HALF_UP once, import, and re-import to
confirm zero duplicate effects. Do not mark owner acceptance complete until
that runtime scenario is actually performed.
