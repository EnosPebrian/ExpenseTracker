# Deterministic CSV dates — BETA-09C

Ordinary and brokerage CSV imports share `CsvDateColumnPolicy`. Detection uses
every nonblank value in the mapped date column, not the first row. A valid ISO
YYYY-MM-DD column always selects ISO. One valid interpretation selects the
format for all rows. Multiple slash interpretations require one explicit
statement-level choice; the mapping UI shows sample ISO results for each choice.

Mixed/inconsistent or invalid columns do not receive a guessed format. Calendar
validation includes leap years. Empty source lines remain ignored by the source
parser; a retained row with a blank required date remains invalid. The existing
explicit format set is preserved, including year-first slash, day-first dash and
named months. Reanalysis applies the chosen format to the whole statement.

Source bytes, row fingerprints and deterministic transaction identity are not
rewritten by format selection. Invalid rows cannot commit. Brokerage invalid
dates remain unresolved (null), never fabricated as epoch dates. No monetary
parsing, rounding, accounting, schema, sync or backup format changes occur.

Generated transaction CSV `date` is the local economic calendar date YYYY-MM-DD.
Created/updated/deleted audit columns retain ISO timestamps. CSV is an exchange
format, not the financial database; encrypted backup compatibility is unchanged.
External-format regression fixtures deliberately retain their source formats.

Owner acceptance — PENDING / NOT RUN: import ISO without a prompt; import a
slash column whose later day >12 proves its order; import a genuinely ambiguous
column and choose once using the examples; verify invalid/mixed dates block.
