# frozen_string_literal: true

module BetterService
  module Workflowable
    # Step - Represents a single step in a workflow pipeline
    #
    # Each step wraps a service class and defines how data flows into it,
    # whether it's optional, conditional execution, and rollback behavior.
    #
    # Example:
    #   step = Step.new(
    #     name: :create_order,
    #     service_class: Order::CreateService,
    #     input: ->(ctx) { { items: ctx.cart_items } },
    #     optional: false,
    #     condition: ->(ctx) { ctx.cart_items.any? },
    #     rollback: ->(ctx) { ctx.order.destroy! }
    #   )
    #
    #   step.call(context, user, params)
    class Step
      attr_reader :name, :service_class, :input_mapper, :optional, :condition, :rollback_block

      def initialize(name:, service_class:, input: nil, optional: false, condition: nil, rollback: nil)
        @name = name
        @service_class = service_class
        @input_mapper = input
        @optional = optional
        @condition = condition
        @rollback_block = rollback
      end

      # Execute the step
      #
      # @param context [Context] The workflow context
      # @param user [Object] The current user
      # @param params [Hash] Base params for the workflow
      # @return [Hash] Service result (normalized to hash format for workflow compatibility)
      def call(context, user, base_params = {})
        # Check if step should be skipped due to condition
        if should_skip?(context)
          return {
            success: true,
            skipped: true,
            message: "Step #{name} skipped due to condition"
          }
        end

        # Build input params for the service
        service_params = build_params(context, base_params)

        # Call the service - returns [object, metadata] tuple
        service_result = service_class.new(user, params: service_params).call

        # Normalize result to hash format (services now return [object, metadata] tuple)
        result = normalize_service_result(service_result)

        # Store result in context if successful
        if result[:success]
          store_result_in_context(context, result)
        elsif optional
          # If step is optional and failed, continue but log the failure
          context.add(:"#{name}_error", result[:errors] || result[:validation_errors])
          return {
            success: true,
            optional_failure: true,
            message: "Optional step #{name} failed but continuing",
            errors: result[:errors] || result[:validation_errors]
          }
        end

        result
      rescue StandardError => e
        # If step is optional, swallow the error and continue
        if optional
          context.add(:"#{name}_error", e.message)
          {
            success: true,
            optional_failure: true,
            message: "Optional step #{name} raised error but continuing",
            error: e.message
          }
        else
          raise e
        end
      end

      # Execute rollback for this step
      #
      # @param context [Context] The workflow context
      # @raise [StandardError] If rollback fails (caught and wrapped by workflow)
      def rollback(context)
        return unless rollback_block

        if rollback_block.is_a?(Proc)
          context.instance_exec(context, &rollback_block)
        else
          rollback_block.call(context)
        end
        # Note: Exceptions are propagated to workflow which wraps them in RollbackError
      end

      private

      # Check if step should be skipped
      def should_skip?(context)
        return false unless condition

        if condition.is_a?(Proc)
          !context.instance_exec(context, &condition)
        else
          !condition.call(context)
        end
      end

      # Build params for service from context
      def build_params(context, base_params)
        if input_mapper
          if input_mapper.is_a?(Proc)
            context.instance_exec(context, &input_mapper)
          else
            input_mapper.call(context)
          end
        else
          base_params
        end
      end

      # Normalize service result from Result format to hash format
      # Services return BetterService::Result but workflows expect hash with :success, :resource, etc.
      #
      # @param service_result [BetterService::Result] The service result
      # @return [Hash] Normalized result hash
      # @raise [BetterService::Errors::Runtime::InvalidResultError] If result is not a BetterService::Result
      def normalize_service_result(service_result)
        unless service_result.is_a?(BetterService::Result)
          raise BetterService::Errors::Runtime::InvalidResultError.new(
            "Step #{name} service must return BetterService::Result, got #{service_result.class}",
            context: { step: name, service: service_class.name, result_class: service_result.class.name }
          )
        end

        object = service_result.resource
        metadata = service_result.meta

        # Build normalized hash result
        result = metadata.dup
        result[:success] = metadata[:success] if metadata.key?(:success)

        # Store object appropriately based on type
        if object.is_a?(Array)
          result[:items] = object
        elsif object.present?
          result[:resource] = object
        end

        result
      end

      # Store successful result data in context
      def store_result_in_context(context, result)
        # Store resource if present
        context.add(name, result[:resource]) if result.key?(:resource)

        # Store items if present
        context.add(name, result[:items]) if result.key?(:items)

        # If neither resource nor items, store the whole result
        if !result.key?(:resource) && !result.key?(:items)
          context.add(name, result)
        end
      end
    end
  end
end
