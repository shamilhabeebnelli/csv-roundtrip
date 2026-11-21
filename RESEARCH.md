# Research and scope

Checked 21 November 2026. This is an original implementation, not a patch to any listed project and not a claim that a source author endorses it.

## Real problem

The GOV.UK Data Standards Authority's CSV guidance discussion records complaints about spreadsheet software silently changing leading zeros, date-like text and other values, and asks for better checking tools:

https://github.com/alphagov/data-standards-authority/issues/1

That is evidence of a real problem, not a ranking of current demand. The discussion is historical; this tool does not claim its feature request remains unresolved.

Microsoft documents leading-zero removal, scientific notation and limits on numerical precision, as well as controls that can prevent some automatic conversions:

https://support.microsoft.com/en-us/excel/keeping-leading-zeros-and-large-numbers

https://support.microsoft.com/en-us/excel/data-import-and-analysis-options-in-excel

These are documented behaviors whose details depend on the Excel version, import path and settings. CSV RoundTrip only reports differences it can observe between the two input files. It cannot prove their cause.

## Existing alternatives

Simon Willison's csv-diff compares CSV or JSON using a unique key and includes values in detailed output. Use it if you need a general data diff:

https://github.com/simonw/csv-diff/

CSV::Excel generates Excel-oriented CSV. It is a different approach, aimed at output formatting rather than after-the-fact auditing:

https://github.com/labocho/csv-excel

This prototype does not generate spreadsheet formulas or wrap values in formula syntax.

## Implementation reference

Ruby's CSV library documents parsing options and field converters. The implementation uses no field converters so the source strings are retained for comparison:

https://ruby.github.io/csv/CSV.html

## Bounded contribution

A local Ruby two-file audit with value-free report output and conservative conversion-pattern labels. There is no promise to recover lost information, emulate spreadsheet applications, validate all CSV dialects or replace a full data-quality system.
