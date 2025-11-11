# frozen_string_literal: true

require "dry-schema"

module BetterService
  module Concerns
    module Serviceable
      module Validatable
        extend ActiveSupport::Concern

        included do
          class_attribute :_schema, default: nil
          attr_reader :validation_errors
        end

        class_methods do
          def schema(&block)
            self._schema = Dry::Schema.Params(&block)
          end

          def schema_defined?
            _schema.present?
          end
        end

        def valid?
          @validation_errors.empty?
        end

        private

        def validate_params!
          return unless self.class._schema

          result = self.class._schema.call(@params)
          return if result.success?

          # Raise ValidationError instead of setting validation_errors
          raise Errors::Runtime::ValidationError.new(
            "Validation failed",
            code: ErrorCodes::VALIDATION_FAILED,
            context: {
              service: self.class.name,
              params: @params,
              validation_errors: format_validation_errors(result.errors)
            }
          )
        end

        def format_validation_errors(errors)
          errors.to_h.transform_values do |messages|
            messages.is_a?(Array) ? messages : [ messages ]
          end
        end
      end
    end
  end
end
