# CSV RoundTrip

![N inside a CSV document motif](logo.svg)

Ruby CLI | Local processing | MIT licensed

Check what changed between an original CSV and the CSV exported after editing it in a spreadsheet. The report shows positions, counts and likely conversion patterns, not the actual contents of cells.

This is a small Ruby command-line tool, not a website. Your files stay on your computer. It never rewrites the source, uploads data, evaluates formulas or fetches links.

## Try it

Requires Ruby with the `csv` and `json` libraries. Ruby installations may package CSV separately; if needed, install the free `csv` gem using your usual Ruby setup. Use a maintained Ruby release for real work. Tested with Ruby 3.0.2 and Ruby 3.4.1. These exact test versions are not recommendations to use an old patch release; use a maintained Ruby and its latest security updates.

```sh
ruby csv-roundtrip original.csv exported.csv
```

In the fictional example, two identifier cells lose leading zeros, one long code changes to scientific notation, one long integer changes digits, and one label gains whitespace. The original and exported files are never changed.

By default, data rows are paired by position. Use this only if rows remain in their original order. Inserted, removed or reordered rows may cause many unrelated cell differences.

If you have a stable unique key, use its column number in the **original** file:

```sh
ruby csv-roundtrip --key 1 keyed-original.csv keyed-exported.csv
```

The key must be nonempty and unique in both files. Header names are matched exactly, so reordered columns are handled. Keys themselves are matched exactly too. If a spreadsheet changes a key, it appears as unmatched on each side. That is not proof a row was added or deleted.

JSON is written to standard output. Redirect it to a file if you want to save it. The tool itself does not create report files.

```sh
ruby csv-roundtrip --limit 100 original.csv exported.csv > report.json
```

Exit codes: `0` means no differences under the implemented checks, `1` means differences, and `2` means the audit could not run. A difference is not necessarily a mistake.

## What the report flags

- Exact changes in cells matched by position or stable key.
- Leading zeros removed while the remaining integer text is equivalent.
- Newly introduced scientific notation.
- Changed values that were originally integer strings of 16 or more digits.
- Whitespace-only changes and quoted-empty versus unquoted-empty representations.
- Columns moved or no longer matched, plus unmatched data-row positions.

A date-like conversion is reported as a generic value change. The tool does not guess a locale or reconstruct dates.

The findings array is capped at 1,000 by default, configurable from 1 to 10,000. Full finding totals and reason counts remain available even when the array is truncated.

## Privacy and limits

The report omits input paths, column header names, key values and cell values. Row and column positions, counts and patterns can still be sensitive. Review it before sharing it. This is data minimization, not anonymity.

Inputs must be comma-separated UTF-8 CSV, with an optional UTF-8 BOM, a nonempty unique header for every column, consistent row widths, no more than 16 MiB per file and no more than 100,000 data rows. Semicolon/tab-separated text is not auto-detected. Header spelling and whitespace are significant. CSV quoting changes are ignored when they decode to the same text, except quoted-empty versus missing content.

The tool does not inspect `.xlsx` files, repair data, recover lost digits, validate all spreadsheet behavior, prove that a change was caused by Excel, identify every formula risk or certify that files are safe to import. Exit `0` is not a compatibility certificate. Use the original source as the record of truth.

No third-party implementation code was copied. See [research notes](RESEARCH.md) for the request evidence and existing alternatives. Generic CSV comparison already exists, including Simon Willison's `csv-diff`; this prototype focuses on conversion-shaped changes and reports that omit actual data values. It is not a claim of novelty.

## Tests

Install the free `minitest` gem if your Ruby installation does not include it, then run:

```sh
ruby test_csv_roundtrip.rb
```

The tests include strict input handling, CSV quoting and multiline cells, BOM/UTF-8 handling, key matching, column reordering, finding limits, error-output minimization and input hash checks to detect mutation.

No hosted service, package-registry publication or third-party outreach is part of this project.

Copyright 2026 Shamil Habeeb Nelli. Code is available under the MIT License.
