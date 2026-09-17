# frozen_string_literal: true

module Verifiabl
  module Issuer
    # Validated public result types returned by Client.
    module Responses
      Registration = Data.define(:verifiabl_reference)
      BarcodeImage = Data.define(:format, :data)
      BarcodeRegistration = Data.define(:verifiabl_reference, :barcode)
      BatchRecord = Data.define(:status, :verifiabl_reference, :external_id, :code, :detail)
      BatchRegistration = Data.define(:results)

      module_function

      def registration(value, expected_reference: nil)
        reference = reference_from(value, "verifiabl_reference")
        if expected_reference && reference != expected_reference
          invalid!("verifiabl_reference does not match the submitted reference")
        end
        Registration.new(verifiabl_reference: reference)
      end

      def barcode_registration(value)
        reference = reference_from(value, "verifiabl_reference")
        barcode = hash(value, "barcode")
        format = string(barcode, "format")
        invalid!("barcode.format must be png") unless format == "png"
        data = string(barcode, "data")
        invalid!("barcode.data must not be empty") if data.empty?
        BarcodeRegistration.new(
          verifiabl_reference: reference,
          barcode: BarcodeImage.new(format: format, data: data)
        )
      end

      def batch_registration(value, expected_records:)
        root = hash_value(value, "response")
        results = root["results"]
        invalid!("results must be an Array") unless results.is_a?(Array)
        invalid!("results must contain one result per submitted record") unless results.length == expected_records.length

        mapped = results.each_with_index.map do |item, index|
          batch_record(item, index, expected_records.fetch(index))
        end
        BatchRegistration.new(results: mapped.freeze)
      end

      def batch_record(value, index, expected_record)
        item = hash_value(value, "results[#{index}]")
        status = string(item, "status")
        invalid!("results[#{index}].status must not be empty") if status.empty?
        reference = reference_from(item, "verifiabl_reference")
        validate_batch_identity!(item, index, expected_record, reference)
        code = optional_string(item, "code")
        invalid!("results[#{index}].code is required for error status") if status == "error" && (code.nil? || code.empty?)
        BatchRecord.new(
          status:,
          verifiabl_reference: reference,
          external_id: optional_string(item, "external_id"),
          code:,
          detail: optional_string(item, "detail")
        )
      end
      private_class_method :batch_record

      def validate_batch_identity!(item, index, expected_record, reference)
        expected = fetch_record(expected_record, :verifiabl_reference)
        invalid!("results[#{index}].verifiabl_reference does not match the submitted record") unless reference == expected

        external_id = optional_string(item, "external_id")
        expected_external_id = optional_record_value(expected_record, :external_id)
        if expected_external_id && external_id != expected_external_id
          invalid!("results[#{index}].external_id does not match the submitted record")
        end
      end
      private_class_method :validate_batch_identity!

      def reference_from(value, key)
        reference = string(hash_value(value, "response"), key)
        Validation.reference!(reference)
      rescue ArgumentError
        invalid!("#{key} must be a valid Verifiabl reference")
      end
      private_class_method :reference_from

      def hash(value, key)
        object = hash_value(value, "response")
        hash_value(object[key], key)
      end
      private_class_method :hash

      def hash_value(value, name)
        invalid!("#{name} must be an object") unless value.is_a?(Hash)
        value
      end
      private_class_method :hash_value

      def string(hash, key)
        value = hash[key]
        invalid!("#{key} must be a String") unless value.is_a?(String)
        value.dup.freeze
      end
      private_class_method :string

      def optional_string(hash, key)
        return nil unless hash.key?(key)
        string(hash, key)
      end
      private_class_method :optional_string

      def fetch_record(record, key)
        return record[key] if record.key?(key)
        return record[key.to_s] if record.key?(key.to_s)
        nil
      end
      private_class_method :fetch_record

      def optional_record_value(record, key)
        fetch_record(record, key)
      end
      private_class_method :optional_record_value

      def invalid!(detail)
        raise TransportError, "Verifiabl API returned an invalid response: #{detail}"
      end
      private_class_method :invalid!
    end
  end
end
