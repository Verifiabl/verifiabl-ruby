# frozen_string_literal: true

require_relative "test_helper"

class PayslipCodesTest < Minitest::Test
  def test_lists_are_discoverable_and_immutable
    expected = {
      Verifiabl::Issuer::PayslipCodes::Australian => %i[
        EARNINGS_TYPES PAID_LEAVE_TYPES ALLOWANCE_TYPES OTHER_ALLOWANCE_CATEGORIES LUMP_SUM_TYPES ETP_TYPES
        ETP_COMPONENTS PAY_FREQUENCIES
      ],
      Verifiabl::Issuer::PayslipCodes::NewZealand => %i[
        EARNINGS_TYPES PAID_LEAVE_TYPES ALLOWANCE_TYPES LEAVE_BALANCE_UNITS
      ]
    }
    expected.each do |namespace, names|
      assert_equal names.sort, namespace.constants(false).sort
      names.each do |name|
        codes = namespace.const_get(name, false)
        refute_empty codes
        assert_equal codes.uniq, codes
        assert codes.frozen?
        assert codes.all?(&:frozen?)
        assert codes.all? { |value| /\A[a-z]+(?:_[a-z]+)*\z/.match?(value) }
      end
    end
  end

  def test_au_and_nz_examples_use_known_codes
    au = Verifiabl::Issuer::PayslipCodes::Australian
    nz = Verifiabl::Issuer::PayslipCodes::NewZealand
    assert_includes au::PAY_FREQUENCIES, "monthly"
    assert_includes au::EARNINGS_TYPES, "paid_leave"
    assert_includes au::EARNINGS_TYPES, "allowance"
    assert_includes au::OTHER_ALLOWANCE_CATEGORIES, "home_office"
    assert_equal %w[a_redundancy a_other b d e], au::LUMP_SUM_TYPES
    assert_equal %w[redundancy other redundancy_split other_split death_dependant death_non_dependant
      death_non_dependant_split death_trustee], au::ETP_TYPES
    assert_equal %w[taxable tax_free], au::ETP_COMPONENTS
    assert_includes au::EARNINGS_TYPES, "lump_sum"
    assert_includes au::EARNINGS_TYPES, "etp"
    refute_includes nz::EARNINGS_TYPES, "etp"
    assert_includes nz::EARNINGS_TYPES, "overtime"
    assert_includes nz::PAID_LEAVE_TYPES, "annual_holiday"
    assert_includes nz::LEAVE_BALANCE_UNITS, "hours"
  end
end
