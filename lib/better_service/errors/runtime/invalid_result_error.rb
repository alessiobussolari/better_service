# frozen_string_literal: true

module BetterService
  module Errors
    module Runtime
      # InvalidResultError - Raised when a service does not return BetterService::Result
      #
      # All services MUST return a BetterService::Result object. This error is raised
      # when a service returns a Hash, Array (tuple), or any other type instead.
      #
      # @example
      #   raise BetterService::Errors::Runtime::InvalidResultError.new(
      #     "Service MyService must return BetterService::Result, got Hash",
      #     context: { service: "MyService", result_class: "Hash" }
      #   )
      class InvalidResultError < RuntimeError
        def initialize(message = nil, code: :invalid_result, context: {}, original_error: nil)
          super(
            message || "Service must return BetterService::Result",
            code: code,
            context: context,
            original_error: original_error
          )
        end
      end
    end
  end
end
