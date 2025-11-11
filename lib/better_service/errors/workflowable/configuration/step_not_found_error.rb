# frozen_string_literal: true

module BetterService
  module Errors
    module Workflowable
      module Configuration
        # Raised when a referenced workflow step is not found
        #
        # This error is raised when trying to access a step that doesn't exist
        # in the workflow definition, such as in dependencies or conditionals.
        #
        # @example Step not found
        #   class MyWorkflow < BetterService::Workflow
        #     step :first_step,
        #          with: FirstService
        #
        #     step :second_step,
        #          with: SecondService,
        #          if: ->(ctx) { ctx.non_existent_step.success? }  # Step doesn't exist
        #   end
        #
        #   MyWorkflow.new(user, params: {}).call
        #   # => raises StepNotFoundError
        class StepNotFoundError < WorkflowConfigurationError
        end
      end
    end
  end
end
