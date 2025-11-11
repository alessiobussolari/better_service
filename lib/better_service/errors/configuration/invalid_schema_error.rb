# frozen_string_literal: true

module BetterService
  module Errors
    module Configuration
      # Raised when a service schema definition is invalid
      #
      # This error is raised when the Dry::Schema definition contains syntax errors
      # or invalid validation rules.
      #
      # @example Invalid schema definition
      #   class MyService < BetterService::Services::Base
      #     schema do
      #       required(:email).filled(:invalid_type)  # Invalid type
      #     end
      #   end
      #
      # @example Schema with syntax error
      #   class MyService < BetterService::Services::Base
      #     schema do
      #       required(:name)  # Missing predicate
      #     end
      #   end
      class InvalidSchemaError < ConfigurationError
      end
    end
  end
end
