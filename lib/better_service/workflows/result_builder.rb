# frozen_string_literal: true

module BetterService
  module Workflows
    # ResultBuilder - Handles construction of success and failure result hashes
    #
    # This module provides methods for building consistent result structures
    # for workflow execution, including metadata tracking and duration measurement.
    module ResultBuilder
      private

      # Build success result
      #
      # @param steps_executed [Array<Symbol>] Names of steps that were executed
      # @param steps_skipped [Array<Symbol>] Names of steps that were skipped
      # @return [Hash] Success result with context and metadata
      def build_success_result(steps_executed: [], steps_skipped: [])
        metadata = {
          workflow: self.class.name,
          steps_executed: steps_executed,
          steps_skipped: steps_skipped,
          duration_ms: duration_ms
        }

        # Include branch decisions if any branches were taken
        metadata[:branches_taken] = @branch_decisions if @branch_decisions.any?

        {
          success: true,
          message: "Workflow completed successfully",
          context: @context,
          metadata: metadata
        }
      end

      # Build failure result
      #
      # @param message [String, nil] Error message
      # @param errors [Hash] Error details
      # @param failed_step [Symbol, nil] Name of the step that failed
      # @param steps_executed [Array<Symbol>] Names of steps that were executed before failure
      # @param steps_skipped [Array<Symbol>] Names of steps that were skipped
      # @return [Hash] Failure result with error details and metadata
      def build_failure_result(message: nil, errors: {}, failed_step: nil, steps_executed: [], steps_skipped: [])
        metadata = {
          workflow: self.class.name,
          failed_step: failed_step,
          steps_executed: steps_executed,
          steps_skipped: steps_skipped,
          duration_ms: duration_ms
        }

        # Include branch decisions if any branches were taken before failure
        metadata[:branches_taken] = @branch_decisions if @branch_decisions.any?

        metadata.delete(:failed_step) if failed_step.nil?

        {
          success: false,
          error: message || @context.errors[:message] || "Workflow failed",
          errors: errors.any? ? errors : @context.errors,
          context: @context,
          metadata: metadata
        }
      end

      # Calculate duration in milliseconds
      #
      # @return [Float, nil] Duration in milliseconds or nil if not available
      def duration_ms
        return nil unless @start_time && @end_time
        (((@end_time - @start_time) * 1000).round(2))
      end
    end
  end
end
