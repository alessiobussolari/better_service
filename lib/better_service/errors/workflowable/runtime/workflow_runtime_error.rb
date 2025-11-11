# frozen_string_literal: true

module BetterService
  module Errors
    module Workflowable
      module Runtime
        # Base class for workflow runtime errors
        #
        # Raised when errors occur during workflow execution, such as step failures,
        # rollback failures, or workflow execution errors.
        #
        # @example Workflow runtime error
        #   class MyWorkflow < BetterService::Workflow
        #     step :first_step,
        #          with: FirstService
        #   end
        #
        #   MyWorkflow.new(user, params: {}).call
        #   # If FirstService fails => raises WorkflowRuntimeError (or subclass)
        class WorkflowRuntimeError < BetterService::Errors::Runtime::RuntimeError
        end
      end
    end
  end
end
