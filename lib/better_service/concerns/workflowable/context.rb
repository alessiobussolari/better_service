# frozen_string_literal: true

module BetterService
  module Workflowable
    # Context - Container for shared data between workflow steps
    #
    # The Context object holds all data that flows through the workflow pipeline.
    # Each step can read from and write to the context. The context also tracks
    # the success/failure state of the workflow.
    #
    # Example:
    #   context = Context.new(user: current_user, cart_items: [...])
    #   context.order = Order.create!(...)
    #   context.success? # => true
    #
    #   context.fail!("Payment failed", payment_error: "Card declined")
    #   context.success? # => false
    #   context.errors # => { payment_error: "Card declined" }
    class Context
      attr_reader :user, :errors, :_called

      def initialize(user, **initial_data)
        @user = user
        @data = initial_data
        @errors = {}
        @failed = false
        @_called = false
      end

      # Check if workflow has succeeded (no failure called)
      def success?
        !@failed
      end

      # Check if workflow has failed
      def failure?
        @failed
      end

      # Mark workflow as failed with error message and optional error details
      #
      # @param message [String] Error message
      # @param errors [Hash] Optional hash of detailed errors
      def fail!(message, **errors)
        @failed = true
        @errors[:message] = message
        @errors.merge!(errors) if errors.any?
      end

      # Mark workflow as called (used internally)
      def called!
        @_called = true
      end

      # Check if workflow has been called
      def called?
        @_called
      end

      # Add data to context
      #
      # @param key [Symbol] Key to store data under
      # @param value [Object] Value to store
      def add(key, value)
        @data[key] = value
      end

      # Get data from context
      #
      # @param key [Symbol] Key to retrieve
      def get(key)
        @data[key]
      end

      # Allow reading context data via method calls
      # Example: context.order instead of context.get(:order)
      def method_missing(method_name, *args)
        method_str = method_name.to_s

        if method_str.end_with?("=")
          # Setter: context.order = value
          key = method_str.chomp("=").to_sym
          @data[key] = args.first
        elsif @data.key?(method_name)
          # Getter: context.order
          @data[method_name]
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        method_str = method_name.to_s
        method_str.end_with?("=") || @data.key?(method_name) || super
      end

      # Return all context data as hash
      def to_h
        @data.dup
      end

      # Inspect for debugging
      def inspect
        "#<BetterService::Workflowable::Context success=#{success?} data=#{@data.inspect} errors=#{@errors.inspect}>"
      end
    end
  end
end
