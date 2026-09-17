# frozen_string_literal: true

require_relative "test_helper"

class ResponsesTest < Minitest::Test
  def test_successful_response_objects_are_deeply_immutable
    source_reference = +"AbCdEfGhIjKlMnOpQrStUv"
    registration = Verifiabl::Issuer::Responses.registration(
      {"verifiabl_reference" => source_reference}
    )
    barcode = Verifiabl::Issuer::Responses.barcode_registration(
      {
        "verifiabl_reference" => source_reference,
        "barcode" => {"format" => "png", "data" => "cG5n"}
      }
    )
    batch = Verifiabl::Issuer::Responses.batch_registration(
      {
        "results" => [
          {
            "status" => "error",
            "verifiabl_reference" => source_reference,
            "external_id" => "pay-1",
            "code" => "INVALID",
            "detail" => "invalid record"
          }
        ]
      },
      expected_records: [{verifiabl_reference: source_reference, external_id: "pay-1"}]
    )

    objects = [registration, barcode, barcode.barcode, batch, batch.results, batch.results.first]
    strings = [
      registration.verifiabl_reference,
      barcode.verifiabl_reference,
      barcode.barcode.format,
      barcode.barcode.data,
      batch.results.first.status,
      batch.results.first.verifiabl_reference,
      batch.results.first.external_id,
      batch.results.first.code,
      batch.results.first.detail
    ]

    objects.each { |object| assert_predicate object, :frozen? }
    strings.each do |string|
      assert_predicate string, :frozen?
      assert_raises(FrozenError) { string.replace("changed") }
    end
    refute_same source_reference, registration.verifiabl_reference
  end
end
