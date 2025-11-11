# frozen_string_literal: true

module BetterService
  # Instrumentation - Provides automatic event publishing for service execution
  #
  # This concern automatically publishes ActiveSupport::Notifications events
  # during the service lifecycle, enabling monitoring, metrics, and observability.
  #
  # Events published:
  # - service.started - When service execution begins
  # - service.completed - When service completes successfully
  # - service.failed - When service raises an exception
  # - cache.hit - When cache lookup returns cached data
  # - cache.miss - When cache lookup requires fresh computation
  #
  # @example Subscribe to all service events
  #   ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
  #     puts "#{payload[:service_name]} took #{payload[:duration]}ms"
  #   end
  #
  # @example Subscribe to specific service
  #   ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
  #     if payload[:service_name] == "ProductsIndexService"
  #       DataDog.histogram("products.index.duration", payload[:duration])
  #     end
  #   end
  module Concerns
    module Instrumentation
      extend ActiveSupport::Concern

      # Hook into prepend to wrap call method
      #
      # This is called when the concern is prepended to a class.
      def self.prepended(base)
        # Always wrap call method
        base.class_eval do
            # Save original call method
            alias_method :call_without_instrumentation, :call

            # Define new call method with instrumentation
            define_method(:call) do
              return call_without_instrumentation unless instrumentation_enabled?

              service_name = self.class.name
              user_id = extract_user_id_from_instance

              # Publish service.started event
              payload = build_start_payload(service_name, user_id)
              ActiveSupport::Notifications.instrument("service.started", payload)

              # Execute the service
              start_time = Time.current

              begin
                result = call_without_instrumentation
                duration = ((Time.current - start_time) * 1000).round(2) # milliseconds

                # Publish service.completed event
                completion_payload = build_completion_payload(
                  service_name, user_id, result, duration
                )
                ActiveSupport::Notifications.instrument("service.completed", completion_payload)

                result
              rescue => error
                duration = ((Time.current - start_time) * 1000).round(2)

                # Extract original error if wrapped in ExecutionError
                original_error = error.respond_to?(:original_error) && error.original_error ? error.original_error : error

                # Publish service.failed event
                failure_payload = build_failure_payload(
                  service_name, user_id, original_error, duration
                )
                ActiveSupport::Notifications.instrument("service.failed", failure_payload)

                # Re-raise the error (don't swallow it)
                raise
              end
            end
          end
      end

      # Check if instrumentation is enabled for this service
      #
      # @return [Boolean]
      def instrumentation_enabled?
        return false unless BetterService.configuration.instrumentation_enabled

        excluded = BetterService.configuration.instrumentation_excluded_services
        full_name = self.class.name

        # Check exact match or if excluded name matches the end of full name
        !excluded.any? { |excluded_name| full_name == excluded_name || full_name.end_with?("::#{excluded_name}") }
      end

      # Extract user ID from service instance
      #
      # @return [Integer, String, nil]
      def extract_user_id_from_instance
        return nil unless respond_to?(:user, true)

        user = send(:user)
        return nil unless user

        user.respond_to?(:id) ? user.id : user
      end

      # Build payload for service.started event
      #
      # @param service_name [String] Name of service class
      # @param user_id [Integer, String, nil] User ID
      # @return [Hash] Event payload
      def build_start_payload(service_name, user_id)
        payload = {
          service_name: service_name,
          user_id: user_id,
          timestamp: Time.current.iso8601
        }

        # Include params if configured and available
        if BetterService.configuration.instrumentation_include_args && respond_to?(:params, true)
          payload[:params] = send(:params)
        end

        payload
      end

      # Build payload for service.completed event
      #
      # @param service_name [String] Name of service class
      # @param user_id [Integer, String, nil] User ID
      # @param result [Object] Service result
      # @param duration [Float] Execution duration in milliseconds
      # @return [Hash] Event payload
      def build_completion_payload(service_name, user_id, result, duration)
        payload = {
          service_name: service_name,
          user_id: user_id,
          duration: duration,
          timestamp: Time.current.iso8601,
          success: true
        }

        # Include params if configured and available
        if BetterService.configuration.instrumentation_include_args && respond_to?(:params, true)
          payload[:params] = send(:params)
        end

        # Include result if configured
        if BetterService.configuration.instrumentation_include_result
          payload[:result] = result
        end

        # Include cache metadata if available
        if result.is_a?(Hash)
          if result.key?(:cache_hit)
            payload[:cache_hit] = result[:cache_hit]
          end
          if result.key?(:cache_key)
            payload[:cache_key] = result[:cache_key]
          end
        end

        payload
      end

      # Build payload for service.failed event
      #
      # @param service_name [String] Name of service class
      # @param user_id [Integer, String, nil] User ID
      # @param error [Exception] The error that was raised
      # @param duration [Float] Execution duration in milliseconds
      # @return [Hash] Event payload
      def build_failure_payload(service_name, user_id, error, duration)
        payload = {
          service_name: service_name,
          user_id: user_id,
          duration: duration,
          timestamp: Time.current.iso8601,
          success: false,
          error_class: error.class.name,
          error_message: error.message
        }

        # Include params if configured and available
        if BetterService.configuration.instrumentation_include_args && respond_to?(:params, true)
          payload[:params] = send(:params)
        end

        # Include backtrace (first 5 lines) for debugging
        if error.backtrace
          payload[:error_backtrace] = error.backtrace.first(5)
        end

        payload
      end

      # Publish cache hit event
      #
      # Called from Cacheable concern when cache lookup succeeds.
      #
      # @param cache_key [String] The cache key that was hit
      # @param context [String] Cache context (e.g., "products")
      # @return [void]
      def publish_cache_hit(cache_key, context = nil)
        return unless instrumentation_enabled?

        payload = {
          service_name: self.class.name,
          event_type: "cache_hit",
          cache_key: cache_key,
          context: context,
          timestamp: Time.current.iso8601
        }

        ActiveSupport::Notifications.instrument("cache.hit", payload)
      end

      # Publish cache miss event
      #
      # Called from Cacheable concern when cache lookup fails.
      #
      # @param cache_key [String] The cache key that missed
      # @param context [String] Cache context (e.g., "products")
      # @return [void]
      def publish_cache_miss(cache_key, context = nil)
        return unless instrumentation_enabled?

        payload = {
          service_name: self.class.name,
          event_type: "cache_miss",
          cache_key: cache_key,
          context: context,
          timestamp: Time.current.iso8601
        }

        ActiveSupport::Notifications.instrument("cache.miss", payload)
      end
    end
  end
end
