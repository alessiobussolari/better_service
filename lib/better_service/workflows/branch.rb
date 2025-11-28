# frozen_string_literal: true

module BetterService
  module Workflows
    # Represents a single conditional branch within a workflow
    #
    # A Branch contains:
    # - A condition (Proc) that determines if the branch should execute
    # - An array of steps to execute if the condition is true
    # - An optional name for identification
    #
    # @example
    #   branch = Branch.new(
    #     condition: ->(ctx) { ctx.user.premium? },
    #     name: :premium_path
    #   )
    #   branch.add_step(step1)
    #   branch.add_step(step2)
    #
    #   if branch.matches?(context)
    #     branch.execute(context, user, params)
    #   end
    class Branch
      attr_reader :condition, :steps, :name

      # Creates a new Branch
      #
      # @param condition [Proc, nil] The condition to evaluate (nil for default/otherwise branch)
      # @param name [Symbol, nil] Optional name for the branch
      def initialize(condition: nil, name: nil)
        @condition = condition
        @steps = []
        @name = name
      end

      # Checks if this branch's condition matches the given context
      #
      # @param context [Workflowable::Context] The workflow context
      # @return [Boolean] true if condition matches or is nil (default branch)
      def matches?(context)
        return true if condition.nil? # Default branch always matches

        if condition.is_a?(Proc)
          context.instance_exec(context, &condition)
        else
          condition.call(context)
        end
      rescue StandardError => e
        Rails.logger.error "Branch condition evaluation failed: #{e.message}"
        false
      end

      # Adds a step to this branch
      #
      # @param step [Workflowable::Step] The step to add
      # @return [Array] The updated steps array
      def add_step(step)
        @steps << step
      end

      # Executes all steps in this branch
      #
      # @param context [Workflowable::Context] The workflow context
      # @param user [Object] The current user
      # @param params [Hash] The workflow parameters
      # @param branch_decisions [Array, nil] Array to track branch decisions for nested branches
      # @return [Array<Workflowable::Step>] Array of successfully executed steps
      # @raise [Errors::Workflowable::Runtime::StepExecutionError] If a required step fails
      def execute(context, user, params, branch_decisions = nil)
        executed_steps = []

        @steps.each do |step_or_branch_group|
          # Handle nested BranchGroup
          if step_or_branch_group.is_a?(BranchGroup)
            branch_result = step_or_branch_group.call(context, user, params)

            # Add executed steps from nested branch
            if branch_result[:executed_steps]
              executed_steps.concat(branch_result[:executed_steps])
            end

            # Track nested branch decisions
            if branch_decisions && branch_result[:branch_decisions]
              branch_decisions.concat(branch_result[:branch_decisions])
            end

            next
          end

          # Handle regular Step
          result = step_or_branch_group.call(context, user, params)

          # Skip if step was skipped
          next if result[:skipped]

          # Handle step failure
          if result[:success] == false && !result[:optional_failure]
            raise Errors::Workflowable::Runtime::StepExecutionError.new(
              "Step #{step_or_branch_group.name} failed in branch",
              code: ErrorCodes::STEP_EXECUTION_FAILED,
              context: {
                step: step_or_branch_group.name,
                branch: @name,
                errors: result[:errors]
              }
            )
          end

          # Track successfully executed steps
          executed_steps << step_or_branch_group unless result[:optional_failure]
        end

        executed_steps
      end

      # Returns whether this is a default branch (no condition)
      #
      # @return [Boolean]
      def default?
        condition.nil?
      end

      # Returns a string representation of this branch
      #
      # @return [String]
      def inspect
        "#<BetterService::Workflows::Branch name=#{@name.inspect} " \
          "condition=#{@condition.present? ? 'present' : 'nil'} " \
          "steps=#{@steps.count}>"
      end
    end
  end
end
