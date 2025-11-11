# frozen_string_literal: true

module BetterService
  module Errors
    module Configuration
      # Raised when a service has invalid configuration settings
      #
      # This error is raised when configuration options are invalid or conflicting,
      # such as invalid cache settings, presenter configurations, or workflow definitions.
      #
      # @example Invalid cache configuration
      #   class MyService < BetterService::Services::Base
      #     config do
      #       cache enabled: true, expires_in: "invalid"  # Should be integer
      #     end
      #   end
      #
      # @example Invalid workflow step
      #   class MyWorkflow < BetterService::Workflow
      #     step :invalid,
      #          with: nil,  # Missing service class
      #          input: -> (ctx) { ctx.data }
      #   end
      class InvalidConfigurationError < ConfigurationError
      end
    end
  end
end
