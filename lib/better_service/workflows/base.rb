# frozen_string_literal: true

module BetterService
  # Workflow - Base class for composing multiple services into a pipeline
  #
  # Workflows allow you to chain multiple services together with explicit
  # data mapping, conditional execution, rollback support, and lifecycle hooks.
  #
  # Example:
  #   class OrderPurchaseWorkflow < BetterService::Workflow
  #     with_transaction true
  #
  #     before_workflow :validate_cart
  #     after_workflow :clear_cart
  #
  #     step :create_order,
  #          with: Order::CreateService,
  #          input: ->(ctx) { { items: ctx.cart_items, total: ctx.total } }
  #
  #     step :charge_payment,
  #          with: Payment::ChargeService,
  #          input: ->(ctx) { { amount: ctx.order.total } },
  #          rollback: ->(ctx) { Payment::RefundService.new(ctx.user, params: { charge_id: ctx.charge.id }).call }
  #
  #     step :send_email,
  #          with: Email::ConfirmationService,
  #          input: ->(ctx) { { order_id: ctx.order.id } },
  #          optional: true,
  #          if: ->(ctx) { ctx.user.notifications_enabled? }
  #
  #     private
  #
  #     def validate_cart(context)
  #       context.fail!("Cart is empty") if context.cart_items.empty?
  #     end
  #
  #     def clear_cart(context)
  #       context.user.clear_cart! if context.success?
  #     end
  #   end
  #
  #   # Usage:
  #   result = OrderPurchaseWorkflow.new(current_user, params: { cart_items: [...] }).call
  #   if result[:success]
  #     order = result[:context].order
  #   else
  #     errors = result[:errors]
  #   end
  module Workflows
    class Base
      include Concerns::Workflowable::Callbacks
      include DSL
      include TransactionSupport
      include Execution
      include RollbackSupport
      include ResultBuilder

      attr_reader :user, :params, :context

    # Initialize a new workflow
    #
    # @param user [Object] The current user executing the workflow
    # @param params [Hash] Parameters for the workflow
    def initialize(user, params: {})
      @user = user
      @params = params
      @context = Workflowable::Context.new(user, **params)
      @executed_steps = []
      @start_time = nil
      @end_time = nil
    end

    # Main entry point - executes the workflow
    #
    # Runs before_workflow callbacks, executes the workflow (with or without
    # transaction), and runs after_workflow callbacks. Tracks timing and
    # ensures callbacks run even if execution fails.
    #
    # @return [Hash] Result hash with success status, context, and metadata
    def call
      @start_time = Time.current
      @context.called!

      # Run before_workflow callbacks
      run_before_workflow_callbacks(@context)

      # If callbacks failed the context, return early
      if @context.failure?
        @end_time = Time.current
        return build_failure_result
      end

      # Execute workflow with or without transaction
      if self.class._use_transaction
        execute_with_transaction
      else
        execute_workflow
      end
    ensure
      @end_time ||= Time.current
      # Always run after_workflow callbacks
      run_after_workflow_callbacks(@context) if @context.called?
    end
    end
  end
end
