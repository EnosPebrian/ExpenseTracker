# Reliability and spreadsheet program — owner acceptance

Engineering verification does not constitute physical-device acceptance.
All checks below: **PENDING / NOT RUN**. Prior explicitly deferred BETA-08N
checks remain **DEFERRED BY OWNER / NOT EXECUTED**, not retroactively passed.
Use a controlled test household and a current build on Windows and Android.
Create an encrypted backup before financial test changes.

| Check | Setup and exact action | Expected result | Owner PASS/FAIL |
| --- | --- | --- | --- |
| Brokerage session replan | Review one test statement with BUY 100, later SELL 40 and SPLIT 2:1 for a new ticker; choose Create once | One definition; later rows validate against the session; excluding BUY blocks dependent SELL/SPLIT; exact reimport adds no effects | NOT RUN |
| Multi-device convergence | Same household on Windows/Android; import reviewed Windows test rows, sync Windows, then Android | Every accepted row and dependency appears once on Android; repeat sync changes nothing | NOT RUN |
| Durable manual merge | Edit one ordinary test transaction differently offline on both devices; reconnect and open Conflict, choose explicit local/cloud fields | Actual resolver opens; conflict remains on network failure; after confirmed resolution both devices converge without losing independent records | NOT RUN |
| CSV dates | Import ISO dates, then DD/MM column containing day 13, then genuinely ambiguous slash dates | ISO/no prompt; whole-column DD/MM detection; ambiguous source asks once with examples; invalid dates cannot commit | NOT RUN |
| Desktop grid | Open Transactions at wide width; sort/resize/scroll, select a description, Enter, edit, Enter; Escape another edit | Local update visible; selected cell/error clear; protected transfer/asset/Tithe uses coordinated editor; phone retains list | NOT RUN |
| Clipboard and bulk | Shift-select ordinary descriptions, Copy into spreadsheet, paste valid text back, inspect review; try invalid amount rectangle; Set category on selected rows | Copy is read-only; review before writes; invalid plan cannot apply; only selected visible rows change; explicit per-row outcomes | NOT RUN |
| Undo and filters | Edit one description then Undo; change row on another device before a second undo attempt; filter account/project/sync state | Undo uses normal new mutation; stale undo refuses; filters never mutate records; catalog/bulk undo is not offered | NOT RUN |
| Offline and restart | Disconnect, edit ordinary grid row, close/reopen, reconnect and sync to Android | Local data survives restart; state remains Pending until acknowledgement; Android receives edit; no duplicate operation effect | NOT RUN |

Known constraints: integer account storage units in amount cells; individually
reviewed row saves rather than atomic multi-row updates; undo only the latest
single-cell text/date/amount edit; no catalog/bulk undo, column hide/reorder or
persisted layout. No Google Sheets primary storage or live bridge is implemented.
Windows is not Authenticode-signed; the existing file_picker Kotlin warning
remains non-blocking. Web remains a development preview.
