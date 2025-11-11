# frozen_string_literal: true

module BetterService
  module Errors
    module Runtime
      # Raised when unexpected error occurs during service execution
      #
      # This error wraps unexpected StandardError exceptions that occur during
      # the service's search, process, transform, or respond phases.
      #
      # @example Unexpected error in service
      #   class MyService < BetterService::Services::Base
      #     schema { }
      #
      #     process_with do |data|
      #       # Some operation that fails unexpectedly
      #       third_party_api.call  # raises SocketError
      #     end
      #   end
      #
      #   MyService.new(user, params: {}).call
      #   # => raises ExecutionError wrapping SocketError
      class ExecutionError < RuntimeError
      end
    end
  end
end
