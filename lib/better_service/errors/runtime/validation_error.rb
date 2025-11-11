# frozen_string_literal: true

module BetterService
  module Errors
    module Runtime
      # Raised when parameter validation fails
      #
      # This error is raised during service initialization when Dry::Schema
      # validation fails. The validation errors are available in the context.
      #
      # @example Validation failure
      #   class MyService < BetterService::Services::Base
      #     schema do
      #       required(:email).filled(:string)
      #       required(:age).filled(:integer, gt?: 18)
      #     end
      #   end
      #
      #   MyService.new(user, params: { email: "", age: 15 }).call
      #   # => raises ValidationError with context:
      #   # {
      #   #   service: "MyService",
      #   #   validation_errors: {
      #   #     email: ["must be filled"],
      #   #     age: ["must be greater than 18"]
      #   #   }
      #   # }
      #
      # @example Handling validation errors
      #   begin
      #     MyService.new(user, params: invalid_params).call
      #   rescue BetterService::Errors::Runtime::ValidationError => e
      #     render json: {
      #       error: e.message,
      #       validation_errors: e.context[:validation_errors]
      #     }, status: :unprocessable_entity
      #   end
      class ValidationError < RuntimeError
      end
    end
  end
end
