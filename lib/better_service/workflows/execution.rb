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

        self.class._steps.each do |step_or_branch|
          # Handle BranchGroup (conditional branching)
          if step_or_branch.is_a?(BranchGroup)
            branch_result = nil
            run_around_step_callbacks(step_or_branch, @context) do
              branch_result = step_or_branch.call(@context, @user, @params)
            end

            # Track branch decisions (including nested)
            if branch_result[:branch_decisions]
              @branch_decisions.concat(branch_result[:branch_decisions])
            end

            # Track executed steps from the branch
            if branch_result[:executed_steps]
              branch_result[:executed_steps].each do |executed_step|
                @executed_steps << executed_step
                steps_executed << executed_step.name
              end
            end

            next
          end

          # Handle regular Step
          result = nil
          run_around_step_callbacks(step_or_branch, @context) do
            result = step_or_branch.call(@context, @user, @params)
          end

          # Track skipped steps
          if result[:skipped]
            steps_skipped << step_or_branch.name
            next
          end

          # If step failed and it's not optional, stop and rollback
          if result[:success] == false && !result[:optional_failure]
            # With Pure Exception Pattern, all failures raise exceptions
            rollback_steps

            raise Errors::Workflowable::Runtime::StepExecutionError.new(
              "Step #{step_or_branch.name} failed: #{result[:error] || result[:message]}",
              code: ErrorCodes::STEP_FAILED,
              context: {
                workflow: self.class.name,
                step: step_or_branch.name,
                steps_executed: steps_executed,
                errors: result[:errors] || {}
              }
            )
          end

          # Track successful execution
          @executed_steps << step_or_branch
          steps_executed << step_or_branch.name
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
      rescue Errors::Configuration::InvalidConfigurationError
        # Configuration error (e.g., no matching branch), just re-raise
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
