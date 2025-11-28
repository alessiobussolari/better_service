# frozen_string_literal: true

module BetterService
  module Workflows
    # DSL - Provides class-level DSL methods for defining workflow steps
    #
    # This module adds the `step` and `with_transaction` class methods that
    # allow declarative workflow definition using a clean DSL syntax.
    module DSL
      extend ActiveSupport::Concern

      included do
        class_attribute :_steps, default: []
        class_attribute :_use_transaction, default: false
      end

      class_methods do
        # DSL method to define a step in the workflow
        #
        # @param name [Symbol] Name of the step
        # @param with [Class] Service class to execute
        # @param input [Proc] Lambda to map context data to service params
        # @param optional [Boolean] Whether step failure should stop the workflow
        # @param if [Proc] Condition to determine if step should execute
        # @param rollback [Proc] Block to execute if rollback is needed
        #
        # @example Define a workflow step
        #   step :create_order,
        #        with: Order::CreateService,
        #        input: ->(ctx) { { items: ctx.cart_items } },
        #        rollback: ->(ctx) { ctx.order.destroy! }
        def step(name, with:, input: nil, optional: false, if: nil, rollback: nil)
          step = Workflowable::Step.new(
            name: name,
            service_class: with,
            input: input,
            optional: optional,
            condition: binding.local_variable_get(:if), # Use binding to get the 'if' keyword param
            rollback: rollback
          )

          self._steps += [ step ]
        end

        # DSL method to define conditional branches in the workflow
        #
        # Creates a branch group that allows multiple conditional execution paths.
        # Only one branch will be executed based on the first matching condition.
        #
        # @param block [Proc] Block containing branch definitions (on/otherwise)
        #
        # @example Define conditional branches
        #   branch do
        #     on ->(ctx) { ctx.user.premium? } do
        #       step :premium_feature, with: PremiumService
        #     end
        #
        #     on ->(ctx) { ctx.user.basic? } do
        #       step :basic_feature, with: BasicService
        #     end
        #
        #     otherwise do
        #       step :default_feature, with: DefaultService
        #     end
        #   end
        def branch(&block)
          raise ArgumentError, "Block required for 'branch'" unless block_given?

          # Count existing branch groups to determine index
          branch_count = _steps.count { |s| s.is_a?(BranchGroup) }

          # Create branch group
          branch_group = BranchGroup.new(name: :"branch_#{branch_count + 1}")

          # Create DSL context and evaluate block
          branch_dsl = BranchDSL.new(branch_group)
          branch_dsl.instance_eval(&block)

          # Validate: must have at least one branch (conditional or default)
          if branch_group.branches.empty? && branch_group.default_branch.nil?
            raise Errors::Configuration::InvalidConfigurationError.new(
              "Branch group must contain at least one 'on' or 'otherwise' block",
              code: ErrorCodes::CONFIGURATION_ERROR
            )
          end

          # Add branch group to steps
          self._steps += [ branch_group ]
        end

        # Enable or disable database transactions for the entire workflow
        #
        # @param enabled [Boolean] Whether to use transactions
        #
        # @example Enable transactions
        #   class MyWorkflow < BetterService::Workflow
        #     with_transaction true
        #   end
        def with_transaction(enabled)
          self._use_transaction = enabled
        end
      end
    end
  end
end
