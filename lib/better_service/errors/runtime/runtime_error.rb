# frozen_string_literal: true

module BetterService
  module Errors
    module Runtime
      # Base class for all runtime errors in BetterService
      #
      # Runtime errors are raised when something goes wrong during service execution
      # due to external factors (database, network, invalid data, etc.).
      # These are not programming errors.
      #
      # @example
      #   raise BetterService::Errors::Runtime::RuntimeError.new(
      #     "Runtime error occurred",
      #     code: :runtime_error,
      #     context: { service: "MyService", operation: "fetch_data" }
      #   )
      class RuntimeError < BetterServiceError
      end
    end
  end
end
