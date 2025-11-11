# frozen_string_literal: true

module BetterService
  module Errors
    module Configuration
      # Base class for all configuration/programming errors in BetterService
      #
      # Configuration errors are raised when a service is incorrectly configured or used.
      # These are programming errors that should be fixed during development.
      #
      # @example
      #   raise BetterService::Errors::Configuration::ConfigurationError.new(
      #     "Invalid service configuration",
      #     code: :configuration_error,
      #     context: { service: "MyService", issue: "missing required config" }
      #   )
      class ConfigurationError < BetterServiceError
      end
    end
  end
end
