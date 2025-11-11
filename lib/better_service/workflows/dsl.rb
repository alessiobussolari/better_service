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
