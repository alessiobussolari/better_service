# frozen_string_literal: true

module BetterService
  module Errors
    module Workflowable
      module Runtime
        # Raised when a workflow step execution fails
        #
        # This error is raised when a step in the workflow fails and the step is not optional.
        # The error includes context about which step failed and what steps were executed.
        #
        # @example Step execution failure
        #   class MyWorkflow < BetterService::Workflow
        #     step :create_user,
        #          with: User::CreateService
        #
        #     step :charge_payment,
        #          with: Payment::ChargeService  # This step fails
        #
        #     step :send_email,
        #          with: Email::WelcomeService  # This step never executes
        #   end
        #
        #   MyWorkflow.new(user, params: {}).call
        #   # => raises StepExecutionError with context:
        #   # {
        #   #   workflow: "MyWorkflow",
        #   #   step: :charge_payment,
        #   #   steps_executed: [:create_user],
        #   #   errors: { ... }
        #   # }
        #
        # @example Optional step failures don't raise
        #   class MyWorkflow < BetterService::Workflow
        #     step :create_user,
        #          with: User::CreateService
        #
        #     step :send_email,
        #          with: Email::WelcomeService,
        #          optional: true  # Failure won't raise StepExecutionError
        #   end
        class StepExecutionError < WorkflowRuntimeError
        end
      end
    end
  end
end
