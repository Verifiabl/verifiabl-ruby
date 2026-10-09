# frozen_string_literal: true

# Generated AU/NZ v2 payslip code discovery lists. Do not edit by hand.
# Discovery only; the API validates non-PII code values.
module Verifiabl
  module Issuer
    module PayslipCodes
      module Australian
        EARNINGS_TYPES = %w[
          paid_leave allowance lump_sum etp ordinary overtime
          bonus_commission directors_fees return_to_work other
        ].map!(&:freeze).freeze

        PAID_LEAVE_TYPES = %w[
          cash_out_in_service unused_on_termination paid_parental workers_compensation ancillary_defence other_paid_leave
        ].map!(&:freeze).freeze

        ALLOWANCE_TYPES = %w[
          cents_per_km award_transport laundry overtime_meal travel tools
          tasks qualifications other
        ].map!(&:freeze).freeze

        OTHER_ALLOWANCE_CATEGORIES = %w[
          home_office non_deductible transport_fares uniform private_vehicle general
        ].map!(&:freeze).freeze

        LUMP_SUM_TYPES = %w[
          a_redundancy a_other b d e
        ].map!(&:freeze).freeze

        ETP_TYPES = %w[
          redundancy other redundancy_split other_split death_dependant death_non_dependant
          death_non_dependant_split death_trustee
        ].map!(&:freeze).freeze

        ETP_COMPONENTS = %w[
          taxable tax_free
        ].map!(&:freeze).freeze

        PAY_FREQUENCIES = %w[
          weekly fortnightly monthly quarterly four_weekly semi_monthly
        ].map!(&:freeze).freeze
      end

      module NewZealand
        EARNINGS_TYPES = %w[
          paid_leave allowance ordinary overtime penal_rate piece_work
          bonus_commission extra_pay schedular_payment directors_fees pay_as_you_go_holiday_pay leave_compensation_payment
          annual_holiday_cash_out alternative_holiday_cash_out holiday_pay_on_termination other
        ].map!(&:freeze).freeze

        PAID_LEAVE_TYPES = %w[
          annual_holiday public_holiday alternative_holiday sick_leave bereavement_leave other_paid_leave
        ].map!(&:freeze).freeze

        ALLOWANCE_TYPES = %w[
          meal travel accommodation vehicle phone tools
          uniform on_call shift first_aid higher_duties qualification
          other
        ].map!(&:freeze).freeze

        LEAVE_BALANCE_UNITS = %w[
          hours days weeks
        ].map!(&:freeze).freeze
      end
    end
  end
end
