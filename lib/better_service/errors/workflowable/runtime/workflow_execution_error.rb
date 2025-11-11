# frozen_string_literal: true

module BetterService
  module Errors
    module Workflowable
      module Runtime
        # Raised when workflow execution fails
        #
        # This error is raised when unexpected errors occur during workflow execution,
        # wrapping the original exception with workflow context.
        #
        # @example Workflow execution failure
        #   class MyWorkflow < BetterService::Workflow
        #     step :create_user,
        #          with: User::CreateService
        #
        #     step :send_email,
        #          with: Email::WelcomeService
        #   end
        #
        #   MyWorkflow.new(user, params: {}).call
        #   # If unexpected error occurs => raises WorkflowExecutionError
        #
        # @example Error context
        #   begin
        #     MyWorkflow.new(user, params: params).call
        #   rescue BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError => e
        #     e.context
        #     # => {
        #     #   workflow: "MyWorkflow",
        #     #   steps_executed: [:create_user],
        #     #   steps_skipped: []
        #     # }
        #   end
        class WorkflowExecutionError < WorkflowRuntimeError
        end
      end
    end
  end
end
