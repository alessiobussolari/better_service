# frozen_string_literal: true

module BetterService
  module Workflows
    # DSL context for defining conditional branches
    #
    # This class provides the DSL methods available inside a `branch do...end` block:
    # - `on(condition, &block)` - Defines a conditional branch
    # - `otherwise(&block)` - Defines the default branch
    # - `step(...)` - Adds a step to the current branch
    # - `branch(&block)` - Allows nested branch groups
    #
    # @example
    #   branch do
    #     on ->(ctx) { ctx.user.premium? } do
    #       step :premium_action, with: PremiumService
    #     end
    #
    #     on ->(ctx) { ctx.user.basic? } do
    #       step :basic_action, with: BasicService
    #     end
    #
    #     otherwise do
    #       step :default_action, with: DefaultService
    #     end
    #   end
    class BranchDSL
      attr_reader :branch_group

      # Creates a new BranchDSL context
      #
      # @param branch_group [BranchGroup] The branch group being configured
      def initialize(branch_group)
        @branch_group = branch_group
        @current_branch = nil
        @branch_index = 0
      end

      # Defines a conditional branch
      #
      # @param condition [Proc] The condition to evaluate (receives context)
      # @param block [Proc] The block defining steps for this branch
      # @return [void]
      #
      # @example
      #   on ->(ctx) { ctx.user.premium? } do
      #     step :send_premium_email, with: Email::PremiumService
      #   end
      def on(condition, &block)
        raise ArgumentError, "Condition must be a Proc" unless condition.is_a?(Proc)
        raise ArgumentError, "Block required for 'on'" unless block_given?

        @branch_index += 1
        branch_name = :"on_#{@branch_index}"

        @current_branch = @branch_group.add_branch(
          condition: condition,
          name: branch_name
        )

        # Evaluate the block in this DSL context
        instance_eval(&block)

        @current_branch = nil
      end

      # Defines the default branch (executed when no condition matches)
      #
      # @param block [Proc] The block defining steps for the default branch
      # @return [void]
      #
      # @example
      #   otherwise do
      #     step :default_action, with: DefaultService
      #   end
      def otherwise(&block)
        raise ArgumentError, "Block required for 'otherwise'" unless block_given?
        raise ArgumentError, "Default branch already defined" if @branch_group.default_branch

        @current_branch = @branch_group.set_default

        # Evaluate the block in this DSL context
        instance_eval(&block)

        @current_branch = nil
      end

      # Adds a step to the current branch
      #
      # This method has the same signature as the workflow-level `step` method.
      #
      # @param name [Symbol] The step name
      # @param with [Class] The service class to execute
      # @param input [Proc, nil] Optional input mapper
      # @param optional [Boolean] Whether the step is optional
      # @param if [Proc, nil] Optional condition for step execution
      # @param rollback [Proc, nil] Optional rollback handler
      # @return [void]
      def step(name, with:, input: nil, optional: false, **options)
        raise "step must be called within an 'on' or 'otherwise' block" unless @current_branch

        # Handle Ruby keyword 'if' gracefully
        condition = options[:if] || options.dig(:binding)&.local_variable_get(:if) rescue nil

        step_obj = Workflowable::Step.new(
          name: name,
          service_class: with,
          input: input,
          optional: optional,
          condition: condition,
          rollback: options[:rollback]
        )

        @current_branch.add_step(step_obj)
      end

      # Allows nested branch groups within branches
      #
      # @param block [Proc] The block defining the nested branch group
      # @return [void]
      #
      # @example
      #   on ->(ctx) { ctx.type == 'contract' } do
      #     step :validate_contract, with: ValidateService
      #
      #     branch do
      #       on ->(ctx) { ctx.value > 10000 } do
      #         step :ceo_approval, with: CEOApprovalService
      #       end
      #       otherwise do
      #         step :manager_approval, with: ManagerApprovalService
      #       end
      #     end
      #   end
      def branch(&block)
        raise "branch must be called within an 'on' or 'otherwise' block" unless @current_branch
        raise ArgumentError, "Block required for 'branch'" unless block_given?

        # Create nested branch group
        nested_group = BranchGroup.new(name: :"nested_branch_#{@branch_index}")
        nested_dsl = BranchDSL.new(nested_group)

        # Evaluate the block in the nested DSL context
        nested_dsl.instance_eval(&block)

        # Add the branch group as a "step" (it responds to call like a step)
        @current_branch.add_step(nested_group)
      end
    end
  end
end
