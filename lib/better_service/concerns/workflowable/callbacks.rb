# frozen_string_literal: true

module BetterService
  module Concerns
    module Workflowable
      # Callbacks - Adds lifecycle callbacks to workflows
    #
    # Provides before_workflow, after_workflow, and around_step hooks
    # that allow executing custom logic at different stages of the workflow.
    #
    # Example:
    #   class OrderWorkflow < BetterService::Workflow
    #     before_workflow :validate_prerequisites
    #     after_workflow :cleanup_resources
    #     around_step :log_step_execution
    #
    #     private
    #
    #     def validate_prerequisites(context)
    #       context.fail!("Cart is empty") if context.cart_items.empty?
    #     end
    #
    #     def cleanup_resources(context)
    #       context.user.clear_cart! if context.success?
    #     end
    #
    #     def log_step_execution(step, context)
    #       start_time = Time.current
    #       yield # Execute the step
    #       duration = Time.current - start_time
    #       Rails.logger.info "Step #{step.name} completed in #{duration}s"
    #     end
    #   end
      module Callbacks
        extend ActiveSupport::Concern

      included do
        class_attribute :_before_workflow_callbacks, default: []
        class_attribute :_after_workflow_callbacks, default: []
        class_attribute :_around_step_callbacks, default: []
      end

      class_methods do
        # Define a callback to run before the workflow starts
        #
        # @param method_name [Symbol] Name of the method to call
        def before_workflow(method_name)
          self._before_workflow_callbacks += [ method_name ]
        end

        # Define a callback to run after the workflow completes
        #
        # @param method_name [Symbol] Name of the method to call
        def after_workflow(method_name)
          self._after_workflow_callbacks += [ method_name ]
        end

        # Define a callback to run around each step execution
        #
        # @param method_name [Symbol] Name of the method to call
        # The method will receive the step and context as arguments
        # and should yield to execute the step
        def around_step(method_name)
          self._around_step_callbacks += [ method_name ]
        end
      end

      private

      # Run all before_workflow callbacks
      def run_before_workflow_callbacks(context)
        self.class._before_workflow_callbacks.each do |callback|
          send(callback, context)
          # Stop execution if context was marked as failed
          break if context.failure?
        end
      end

      # Run all after_workflow callbacks
      def run_after_workflow_callbacks(context)
        self.class._after_workflow_callbacks.each do |callback|
          send(callback, context)
        end
      end

      # Run around_step callbacks for a specific step
      def run_around_step_callbacks(step, context, &block)
        callbacks = self.class._around_step_callbacks.dup

        if callbacks.empty?
          # No callbacks, just execute the block
          yield
        else
          # Build a chain of callbacks
          execute_callback_chain(callbacks, step, context, &block)
        end
      end

      # Execute callback chain recursively
      def execute_callback_chain(callbacks, step, context, &block)
        if callbacks.empty?
          # End of chain, execute the actual step
          yield
        else
          # Pop the first callback and execute it
          callback = callbacks.shift
          send(callback, step, context) do
            # Continue the chain
            execute_callback_chain(callbacks, step, context, &block)
          end
        end
      end
      end
    end
  end
end
