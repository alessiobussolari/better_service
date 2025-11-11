# frozen_string_literal: true

module BetterService
  module Errors
    module Workflowable
      module Configuration
        # Base class for workflow configuration errors
        #
        # Raised when a workflow is incorrectly configured, such as invalid steps,
        # missing service classes, or conflicting configurations.
        #
        # @example Invalid workflow configuration
        #   class MyWorkflow < BetterService::Workflow
        #     step :invalid,
        #          with: nil  # Missing service class
        #   end
        #
        #   # => raises WorkflowConfigurationError during class definition
        class WorkflowConfigurationError < BetterService::Errors::Configuration::ConfigurationError
        end
      end
    end
  end
end
