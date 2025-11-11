# frozen_string_literal: true

module BetterService
  module Errors
    module Configuration
      # Raised when a service is missing a required schema definition
      #
      # All BetterService services must define a schema block for parameter validation.
      # This error is raised during service initialization if no schema is defined.
      #
      # @example Service without schema (will raise error)
      #   class MyService < BetterService::Services::Base
      #     # Missing: schema do ... end
      #   end
      #
      #   MyService.new(user, params: {})
      #   # => raises SchemaRequiredError
      #
      # @example Correct usage with schema
      #   class MyService < BetterService::Services::Base
      #     schema do
      #       required(:name).filled(:string)
      #     end
      #   end
      class SchemaRequiredError < ConfigurationError
      end
    end
  end
end
