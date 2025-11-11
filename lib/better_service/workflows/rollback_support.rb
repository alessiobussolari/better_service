# frozen_string_literal: true

module BetterService
  module Workflows
    # RollbackSupport - Handles rollback of executed steps when workflow fails
    #
    # This module provides the rollback mechanism that executes step rollback
    # blocks in reverse order when a workflow execution fails.
    module RollbackSupport
      private

      # Rollback all executed steps in reverse order
      #
      # Iterates through executed steps in reverse and calls their rollback method.
      # If any rollback fails, raises a RollbackError with context about which
      # step failed and what steps were executed.
      #
      # @raise [Errors::Workflowable::Runtime::RollbackError] If any rollback fails
      # @return [void]
      def rollback_steps
        @executed_steps.reverse_each do |step|
          begin
            step.rollback(@context)
          rescue StandardError => e
            # Rollback failure is serious - raise exception
            Rails.logger.error "Rollback failed for step #{step.name}: #{e.message}" if defined?(Rails)
            Rails.logger.error e.backtrace.join("\n") if defined?(Rails)

            raise Errors::Workflowable::Runtime::RollbackError.new(
              "Rollback failed for step #{step.name}: #{e.message}",
              code: ErrorCodes::ROLLBACK_FAILED,
              original_error: e,
              context: {
                workflow: self.class.name,
                step: step.name,
                executed_steps: @executed_steps.map(&:name)
              }
            )
          end
        end
      end
    end
  end
end
