# frozen_string_literal: true

module BetterService
  module Errors
    module Runtime
      # Raised when a database operation fails
      #
      # This error wraps ActiveRecord database errors such as RecordInvalid,
      # RecordNotSaved, constraint violations, and other database-level failures.
      #
      # @example Record validation fails
      #   class UserCreateService < BetterService::Services::CreateService
      #     model_class User
      #
      #     schema do
      #       required(:email).filled(:string)
      #     end
      #   end
      #
      #   UserCreateService.new(user, params: { email: "invalid" }).call
      #   # => raises DatabaseError wrapping ActiveRecord::RecordInvalid
      #
      # @example Constraint violation
      #   class MyService < BetterService::Services::Base
      #     schema { required(:user_id).filled(:integer) }
      #
      #     process_with do |data|
      #       User.create!(email: "duplicate@example.com")  # Unique constraint fails
      #     end
      #   end
      #
      #   MyService.new(user, params: { user_id: 1 }).call
      #   # => raises DatabaseError
      class DatabaseError < RuntimeError
      end
    end
  end
end
