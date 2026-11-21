# frozen_string_literal: true
require 'csv'
require 'json'

module CsvRoundtrip
  VERSION = '0.1.0'
  MAX_BYTES = 16 * 1024 * 1024
  MAX_ROWS = 100_000
  class InputError < StandardError; end
  Table = Struct.new(:headers, :rows)

  def self.load(path, input_number)
    raise InputError, "Input #{input_number} is not a regular file" unless File.file?(path)
    bytes = File.open(path, 'rb') { |file| file.read(MAX_BYTES + 1) }
    raise InputError, "Input #{input_number} exceeds 16 MiB" if bytes.bytesize > MAX_BYTES
    text = bytes.force_encoding(Encoding::UTF_8)
    raise InputError, "Input #{input_number} must be UTF-8" unless text.valid_encoding?
    parse(text.sub(/\A\uFEFF/, ''), input_number)
  rescue SystemCallError, IOError
    raise InputError, "Could not read input #{input_number}"
  end

  def self.parse(text, number = 1)
    records = CSV.parse(text, converters: nil, skip_blanks: false, liberal_parsing: false)
    headers = records.shift
    if headers.nil? || headers.empty? || headers.any? { |h| h.nil? || h.strip.empty? }
      raise InputError, "Input #{number} needs a nonempty header in every column"
    end
    raise InputError, "Input #{number} has duplicate headers" unless headers.uniq.length == headers.length
    raise InputError, "Input #{number} exceeds 100000 data rows" if records.length > MAX_ROWS
    unless records.all? { |row| row.length == headers.length }
      raise InputError, "Input #{number} has a row whose width differs from its header"
    end
    Table.new(headers, records)
  rescue CSV::MalformedCSVError, ArgumentError
    raise InputError, "Input #{number} is not valid comma-separated CSV"
  end

  def self.reason(before, after)
    return 'empty_representation_changed' if [before, after].all? { |v| v.nil? || v.empty? }
    return 'whitespace_changed' if before && after && before.strip == after.strip
    if before && after && before.match?(/\A0+\d+\z/) && after.match?(/\A\d+\z/)
      normalize = ->(v) { v.sub(/\A0+(?=\d)/, '') }
      return 'leading_zeros_removed' if normalize.call(before) == normalize.call(after)
    end
    if after && after.match?(/\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)[eE][+-]?\d+\z/) &&
       before && !before.match?(/[eE]/)
      return 'scientific_notation_introduced'
    end
    return 'long_integer_changed' if before && before.match?(/\A[+-]?\d{16,}\z/)
    'value_changed'
  end

  def self.compare(before, after, key: nil, limit: 1000)
    raise InputError, 'Finding limit must be between 1 and 10000' unless (1..10_000).cover?(limit)
    report = {
      tool: 'csv-roundtrip', version: VERSION, mode: key ? 'exact_key' : 'position',
      rows_before: before.rows.length, rows_after: after.rows.length,
      columns_before: before.headers.length, columns_after: after.headers.length,
      matched_rows: 0, changed_cells: 0, finding_count: 0,
      findings: [], reason_counts: {},
      caveats: [
        'Reports omit paths, header names, key values and cell values. Counts and positions can still be sensitive.',
        'Changes may be intentional. Reasons describe observed patterns, not proven spreadsheet behavior.',
        'No repair, deletion detection, full spreadsheet validation or anonymity guarantee is provided.',
        'Indexes are one-based data-row and column positions, excluding the header row.',
        key ? 'Keys match exact text. Edited keys appear as unmatched rows; they are not proof of additions or deletions.' :
              'Rows are paired by position. Insertions, deletions or reordering may produce many unrelated cell differences.'
      ]
    }
    emit = lambda do |finding|
      report[:finding_count] += 1
      code = finding.fetch(:code)
      report[:reason_counts][code] = report[:reason_counts].fetch(code, 0) + 1
      report[:findings] << finding if report[:findings].length < limit
    end
    after_columns = after.headers.each_with_index.to_h
    before_columns = before.headers.each_with_index.to_h
    shared = []
    before.headers.each_with_index do |name, index|
      if after_columns.key?(name)
        other = after_columns.fetch(name)
        shared << [index, other]
        emit.call(code: 'column_moved', column_before: index + 1, column_after: other + 1) if other != index
      else
        emit.call(code: 'column_unmatched_before', column_before: index + 1)
      end
    end
    after.headers.each_with_index do |name, index|
      emit.call(code: 'column_unmatched_after', column_after: index + 1) unless before_columns.key?(name)
    end
    pairs = []
    if key
      unless key.is_a?(Integer) && key.positive? && key <= before.headers.length
        raise InputError, 'Key must be a one-based column number in input 1'
      end
      other_key = after_columns[before.headers[key - 1]]
      raise InputError, 'Key column header must exist unchanged in input 2' unless other_key
      indexes = [[before, key - 1, 1], [after, other_key, 2]].map do |table, column, input|
        result = {}
        table.rows.each_with_index do |row, index|
          value = row[column]
          raise InputError, "Input #{input} has an empty key" if value.nil? || value.empty?
          raise InputError, "Input #{input} has a duplicate key" if result.key?(value)
          result[value] = index
        end
        result
      end
      indexes[0].each do |value, index|
        if indexes[1].key?(value)
          pairs << [index, indexes[1].fetch(value)]
        else
          emit.call(code: 'row_unmatched_before', row_before: index + 1)
        end
      end
      indexes[1].each do |value, index|
        emit.call(code: 'row_unmatched_after', row_after: index + 1) unless indexes[0].key?(value)
      end
    else
      [before.rows.length, after.rows.length].min.times { |i| pairs << [i, i] }
      (pairs.length...before.rows.length).each { |i| emit.call(code: 'tail_unmatched_before', row_before: i + 1) }
      (pairs.length...after.rows.length).each { |i| emit.call(code: 'tail_unmatched_after', row_after: i + 1) }
    end
    report[:matched_rows] = pairs.length
    pairs.each do |left, right|
      shared.each do |a, b|
        old, current = before.rows[left][a], after.rows[right][b]
        next if old == current
        report[:changed_cells] += 1
        emit.call(code: reason(old, current), row_before: left + 1, row_after: right + 1,
                  column_before: a + 1, column_after: b + 1)
      end
    end
    report[:truncated] = report[:finding_count] > report[:findings].length
    report
  end
end
