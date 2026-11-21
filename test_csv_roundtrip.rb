# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'open3'
require 'rbconfig'
require 'digest'
require_relative 'csv_roundtrip'

class CsvRoundtripTest < Minitest::Test
  def table(text)
    CsvRoundtrip.parse(text)
  end
  def audit(left, right, **opts)
    CsvRoundtrip.compare(table(left), table(right), **opts)
  end
  def test_unchanged
    assert_equal 0, audit("id,name\n01,Ada\n", "id,name\n01,Ada\n")[:finding_count]
  end
  def test_leading_zeros
    r = audit("id\n000123\n", "id\n123\n")
    assert_equal 'leading_zeros_removed', r[:findings][0][:code]
  end
  def test_all_zero_identifier
    assert_equal 'leading_zeros_removed', CsvRoundtrip.reason('000', '0')
  end
  def test_different_numbers_not_zero_loss
    assert_equal 'value_changed', CsvRoundtrip.reason('0012', '13')
  end
  def test_scientific_notation
    assert_equal 'scientific_notation_introduced', CsvRoundtrip.reason('12345678901234567', '1.23457E+16')
  end
  def test_unchanged_scientific_value_generic_change
    assert_equal 'value_changed', CsvRoundtrip.reason('1e5', '2e5')
  end
  def test_long_integer
    assert_equal 'long_integer_changed', CsvRoundtrip.reason('12345678901234567', '12345678901234500')
  end
  def test_whitespace
    assert_equal 'whitespace_changed', CsvRoundtrip.reason(' Ada ', 'Ada')
  end
  def test_empty_quoted_representation
    assert_equal 'empty_representation_changed', CsvRoundtrip.reason(nil, '')
  end
  def test_multiline_quoted_cell
    r = audit("id,note\n1,\"hello\nworld\"\n", "id,note\n1,\"hello\nthere\"\n")
    assert_equal 1, r[:changed_cells]
    assert_equal 1, r[:findings][0][:row_before]
  end
  def test_bom_load
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'input.csv')
      File.binwrite(file, "\xEF\xBB\xBFid\n1\n")
      assert_equal ['id'], CsvRoundtrip.load(file, 1).headers
    end
  end
  def test_invalid_utf8
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'secret-path.csv')
      File.binwrite(file, "id\n\xFF\n")
      error = assert_raises(CsvRoundtrip::InputError) { CsvRoundtrip.load(file, 1) }
      refute_includes error.message, 'secret-path'
    end
  end
  def test_duplicate_header
    assert_raises(CsvRoundtrip::InputError) { table("id,id\n1,2\n") }
  end
  def test_blank_header
    assert_raises(CsvRoundtrip::InputError) { table("id, \n1,2\n") }
  end
  def test_ragged_rows
    assert_raises(CsvRoundtrip::InputError) { table("id,name\n1\n") }
  end
  def test_malformed_quotes
    assert_raises(CsvRoundtrip::InputError) { table("id\n\"bad\n") }
  end
  def test_empty_file
    assert_raises(CsvRoundtrip::InputError) { table('') }
  end
  def test_header_only
    assert_equal 0, audit("id\n", "id\n")[:matched_rows]
  end
  def test_reordered_columns
    r = audit("id,name\n1,Ada\n", "name,id\nAda,1\n")
    assert_equal 0, r[:changed_cells]
    assert_equal 2, r[:reason_counts]['column_moved']
  end
  def test_changed_header_not_silent
    r = audit("id,name\n1,Ada\n", "id,title\n1,Ada\n")
    assert_equal 1, r[:reason_counts]['column_unmatched_before']
    assert_equal 1, r[:reason_counts]['column_unmatched_after']
  end
  def test_key_reorders_rows
    r = audit("id,name\n1,Ada\n2,Lin\n", "id,name\n2,Lin\n1,Ada\n", key: 1)
    assert_equal 0, r[:finding_count]
    assert_equal 2, r[:matched_rows]
  end
  def test_key_column_moves
    r = audit("id,name\n1,Ada\n", "name,id\nAda,1\n", key: 1)
    assert_equal 0, r[:changed_cells]
  end
  def test_key_duplicate_refused
    assert_raises(CsvRoundtrip::InputError) { audit("id\n1\n1\n", "id\n1\n", key: 1) }
  end
  def test_key_empty_refused
    assert_raises(CsvRoundtrip::InputError) { audit("id,n\n,Ada\n", "id,n\n1,Ada\n", key: 1) }
  end
  def test_key_out_of_range
    assert_raises(CsvRoundtrip::InputError) { audit("id\n1\n", "id\n1\n", key: 2) }
  end
  def test_key_renamed_header_refused
    assert_raises(CsvRoundtrip::InputError) { audit("id\n1\n", "ID\n1\n", key: 1) }
  end
  def test_edited_key_unmatched_not_deleted
    r = audit("id\n001\n", "id\n1\n", key: 1)
    assert_equal 0, r[:matched_rows]
    assert_equal %w[row_unmatched_before row_unmatched_after], r[:findings].map { |f| f[:code] }
  end
  def test_positional_tail
    r = audit("id\n1\n2\n", "id\n1\n")
    assert_equal 'tail_unmatched_before', r[:findings][0][:code]
  end
  def test_report_contains_no_values_headers_or_paths
    r = audit("secret_header\nsecret_cell\n", "secret_header\nnew_secret\n")
    json = JSON.generate(r)
    %w[secret_header secret_cell new_secret].each { |secret| refute_includes json, secret }
  end
  def test_truncation_retains_totals
    r = audit("id\n01\n02\n03\n", "id\n1\n2\n3\n", limit: 1)
    assert_equal 3, r[:finding_count]
    assert_equal 1, r[:findings].length
    assert_equal true, r[:truncated]
  end
  def test_zero_limit_refused
    assert_raises(CsvRoundtrip::InputError) { audit("id\n", "id\n", limit: 0) }
  end
  def test_cli_no_mutation_and_no_secret_output
    Dir.mktmpdir do |dir|
      first, second = %w[original.csv exported.csv].map { |n| File.join(dir, n) }
      File.write(first, "private_header\n001\n")
      File.write(second, "private_header\n1\n")
      hashes = [first, second].map { |p| Digest::SHA256.file(p).hexdigest }
      out, err, status = Open3.capture3(RbConfig.ruby, File.expand_path('csv-roundtrip', __dir__), first, second)
      assert_equal 1, status.exitstatus
      assert_empty err
      assert_equal 1, JSON.parse(out)['changed_cells']
      refute_includes out, 'private_header'
      refute_includes out, first
      assert_equal hashes, [first, second].map { |p| Digest::SHA256.file(p).hexdigest }
    end
  end
  def test_cli_error_no_input_echo
    _out, err, status = Open3.capture3(RbConfig.ruby, File.expand_path('csv-roundtrip', __dir__), '--secret-payload')
    assert_equal 2, status.exitstatus
    refute_includes err, 'secret-payload'
  end
end
