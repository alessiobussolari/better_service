# frozen_string_literal: true

module BetterService
  module Errors
    module Runtime
      # Raised when a database transaction fails
      #
      # This error is raised when ActiveRecord transaction operations fail,
      # such as deadlocks, serialization errors, or constraint violations.
      #
      # @example Transaction failure
      #   class MyService < BetterService::Services::Base
      #     config do
      #       use_transaction true
      #     end
      #
      #     schema { }
      #
      #     process_with do |data|
      #       # Database operation that causes deadlock
      #       User.transaction do
      #         user.lock!
      #         other_user.lock!  # Deadlock!
      #       end
      #     end
      #   end
      #
      #   MyService.new(user, params: {}).call
      #   # => raises TransactionError
      class TransactionError < RuntimeError
      end
    end
  end
end
