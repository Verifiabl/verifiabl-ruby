# frozen_string_literal: true

# Generated from contracts/pii/jurisdiction-pii-profile-vectors-v1.json. Do not edit.
module Verifiabl
  module Issuer
    module JurisdictionPiiProfiles
      PAYLOAD_MAX_BYTES = 1024
      AUSTRALIAN_MARKER = "AU2"
      NEW_ZEALAND_MARKER = "NZ2"
      AUSTRALIAN_PROFILE_ID = "io.verifiabl.au2-pii-text.v1"
      NEW_ZEALAND_PROFILE_ID = "io.verifiabl.nz2-pii-text.v1"
      AUSTRALIAN_FIELD_ORDER = %i[employee_name position department employer_identity bsb account_number account_name address].freeze
      NEW_ZEALAND_FIELD_ORDER = %i[employee_name ird_number position department employer_name account_number account_name address].freeze
    end
  end
end
