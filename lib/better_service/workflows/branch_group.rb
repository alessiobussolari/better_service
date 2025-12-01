# frozen_string_literal: true

module BetterService
  module Workflows
    # Represents a group of conditional branches in a workflow
    #
    # A BranchGroup is created by the `branch do...end` DSL block and contains:
    # - Multiple conditional branches (from `on` blocks)
    # - An optional default branch (from `otherwise` block)
    #
    # When executed, it evaluates conditions in order and executes the first matching branch.
    # If no branch matches and there's no default, it raises an error.
    #
    # @example
    #   branch_group = BranchGroup.new(name: :payment_routing)
    #   branch_group.add_branch(condition: ->(ctx) { ctx.type == 'card' }) do
    #     # steps...
    #   end
    #   branch_group.set_default do
    #     # default steps...
    #   end
    #
    #   result = branch_group.call(context, user, params)
    class BranchGroup
      attr_reader :branches, :default_branch, :name

      # Creates a new BranchGroup
      #
      # @param name [Symbol, nil] Optional name for the branch group
      def initialize(name: nil)
        @branches = []
        @default_branch = nil
        @name = name
      end

      # Adds a conditional branch to this group
      #
      # @param condition [Proc] The condition to evaluate
      # @param name [Symbol, nil] Optional name for the branch
      # @return [Branch] The created branch
      def add_branch(condition:, name: nil)
        branch = Branch.new(condition: condition, name: name)
        @branches << branch
        branch
      end

      # Sets the default branch (otherwise)
      #
      # @param name [Symbol, nil] Optional name for the default branch
      # @return [Branch] The created default branch
      def set_default(name: nil)
        @default_branch = Branch.new(condition: nil, name: name || :otherwise)
      end

      # Selects the first branch that matches the context
      #
      # @param context [Workflowable::Context] The workflow context
      # @return [Branch, nil] The matching branch or nil if none match
      def select_branch(context)
        # Try conditional branches first (in order)
        @branches.each do |branch|
          return branch if branch.matches?(context)
        end

        # Fall back to default branch if present
        @default_branch
      end

      # Executes the appropriate branch based on context
      #
      # This is called during workflow execution. It:
      # 1. Selects the matching branch
      # 2. Executes all steps in that branch
      # 3. Returns metadata about the execution
      #
      # @param context [Workflowable::Context] The workflow context
      # @param user [Object] The current user
      # @param params [Hash] The workflow parameters
      # @param parent_decisions [Array, nil] Parent branch decisions for nested tracking
      # @return [Hash] Execution result with :executed_steps, :branch_taken, :branch_decisions, :skipped
      # @raise [Errors::Configuration::InvalidConfigurationError] If no branch matches
      def call(context, user, params, parent_decisions = nil)
        selected_branch = select_branch(context)

        if selected_branch.nil?
          raise Errors::Configuration::InvalidConfigurationError.new(
            "No matching branch found and no default branch defined",
            code: ErrorCodes::CONFIGURATION_ERROR,
            context: {
              branch_group: @name,
              branches_count: @branches.count,
              has_default: !@default_branch.nil?
            }
          )
        end

        # Track this branch decision
        branch_decision = "#{@name}:#{selected_branch.name}"
        branch_decisions = [ branch_decision ]

        # Execute the selected branch
        executed_steps = selected_branch.execute(context, user, params, branch_decisions)

        # Return execution metadata
        {
          executed_steps: executed_steps,
          branch_taken: selected_branch,
          branch_decisions: branch_decisions,
          skipped: false
        }
      end

      # Returns the total number of branches (including default)
      #
      # @return [Integer]
      def branch_count
        count = @branches.count
        count += 1 if @default_branch
        count
      end

      # Returns whether this group has a default branch
      #
      # @return [Boolean]
      def has_default?
        !@default_branch.nil?
      end

      # Returns a string representation of this branch group
      #
      # @return [String]
      def inspect
        "#<BetterService::Workflows::BranchGroup name=#{@name.inspect} " \
          "branches=#{@branches.count} " \
          "has_default=#{has_default?}>"
      end
    end
  end
end
