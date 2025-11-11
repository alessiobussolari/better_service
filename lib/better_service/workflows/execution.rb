# frozen_string_literal: true

module BetterService
  module Workflows
    # Execution - Core workflow execution engine
    #
    # This module handles the sequential execution of workflow steps,
    # error handling, and step tracking.
    module Execution
      private

      # Execute workflow steps sequentially
      #
      # Iterates through all defined steps, executing each with around_step callbacks.
      # Tracks executed and skipped steps. Handles step failures by rolling back
      # previously executed steps and raising appropriate errors.
      #
      # @return [Hash] Success or failure result
      # @raise [Errors::Workflowable::Runtime::StepExecutionError] If a step fails
      # @raise [Errors::Workflowable::Runtime::WorkflowExecutionError] If workflow execution fails
      def execute_workflow
        steps_executed = []
        steps_skipped = []

        self.class._steps.each do |step|
          # Execute step with around_step callbacks
          result = nil
          run_around_step_callbacks(step, @context) do
            result = step.call(@context, @user, @params)
          end

          # Track skipped steps
          if result[:skipped]
            steps_skipped << step.name
            next
          end

          # If step failed and it's not optional, stop and rollback
          if result[:success] == false && !result[:optional_failure]
            # With Pure Exception Pattern, all failures raise exceptions
            rollback_steps

            raise Errors::Workflowable::Runtime::StepExecutionError.new(
              "Step #{step.name} failed: #{result[:error] || result[:message]}",
              code: ErrorCodes::STEP_FAILED,
              context: {
                workflow: self.class.name,
                step: step.name,
                steps_executed: steps_executed,
                errors: result[:errors] || {}
              }
            )
          end

          # Track successful execution
          @executed_steps << step
          steps_executed << step.name
        end

        # All steps succeeded
        @end_time = Time.current
        build_success_result(
          steps_executed: steps_executed,
          steps_skipped: steps_skipped
        )
      rescue Errors::Workflowable::Runtime::StepExecutionError
        # Step error already raised, just re-raise
        raise
      rescue StandardError => e
        # Unexpected error during workflow execution
        rollback_steps

        Rails.logger.error "Workflow error: #{e.message}" if defined?(Rails)
        Rails.logger.error e.backtrace.join("\n") if defined?(Rails)

        raise Errors::Workflowable::Runtime::WorkflowExecutionError.new(
          "Workflow execution failed: #{e.message}",
          code: ErrorCodes::WORKFLOW_FAILED,
          original_error: e,
          context: {
            workflow: self.class.name,
            steps_executed: steps_executed,
            steps_skipped: steps_skipped
          }
        )
      end
    end
  end
end
