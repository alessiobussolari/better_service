# frozen_string_literal: true

module BetterService
  module Errors
    module Workflowable
      module Runtime
        # Raised when workflow rollback fails
        #
        # This error is raised when a step's rollback block fails during workflow rollback.
        # Rollback failures are serious as they may leave the system in an inconsistent state.
        #
        # @example Rollback failure
        #   class MyWorkflow < BetterService::Workflow
        #     step :create_user,
        #          with: User::CreateService,
        #          rollback: ->(ctx) { ctx.user.destroy! }
        #
        #     step :charge_payment,
        #          with: Payment::ChargeService,
        #          rollback: ->(ctx) {
        #            # Rollback fails - payment gateway is down
        #            PaymentGateway.refund(ctx.charge.id)  # raises error
        #          }
        #
        #     step :send_email,
        #          with: Email::WelcomeService  # This step fails
        #   end
        #
        #   MyWorkflow.new(user, params: {}).call
        #   # => send_email fails, triggers rollback
        #   # => charge_payment rollback fails
        #   # => raises RollbackError with context:
        #   # {
        #   #   workflow: "MyWorkflow",
        #   #   step: :charge_payment,
        #   #   executed_steps: [:create_user, :charge_payment]
        #   # }
        #
        # @note Rollback errors indicate potential data inconsistency and should be
        #   monitored and handled carefully in production systems.
        class RollbackError < WorkflowRuntimeError
        end
      end
    end
  end
end
