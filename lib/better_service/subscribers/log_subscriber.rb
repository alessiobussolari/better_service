# frozen_string_literal: true

module BetterService
  module Subscribers
    # LogSubscriber - Built-in subscriber that logs service events
    #
    # This subscriber logs all service events to Rails.logger.
    # Enable it in configuration to get automatic logging for all services.
    #
    # @example Enable in initializer
    #   BetterService.configure do |config|
    #     config.log_subscriber_enabled = true
    #     config.log_subscriber_level = :info
    #   end
    class LogSubscriber
      class << self
        # Storage for ActiveSupport::Notifications subscriptions
        #
        # @return [Array<ActiveSupport::Notifications::Fanout::Subscriber>]
        attr_reader :subscriptions

        # Attach the subscriber to ActiveSupport::Notifications
        #
        # This method is called automatically when subscriber is enabled.
        # It subscribes to all service.* events.
        #
        # @return [void]
        def attach
          @subscriptions ||= []
          subscribe_to_service_events
          subscribe_to_cache_events
        end

        # Detach the subscriber from ActiveSupport::Notifications
        #
        # Removes all subscriptions. Useful for testing.
        #
        # @return [void]
        def detach
          if @subscriptions
            @subscriptions.each do |subscription|
              ActiveSupport::Notifications.unsubscribe(subscription)
            end
          end
          @subscriptions = []
        end

        private

        # Subscribe to service lifecycle events
        #
        # @return [void]
        def subscribe_to_service_events
          @subscriptions << ActiveSupport::Notifications.subscribe("service.started") do |name, start, finish, id, payload|
            log_service_started(payload)
          end

          @subscriptions << ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
            log_service_completed(payload)
          end

          @subscriptions << ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
            log_service_failed(payload)
          end
        end

        # Subscribe to cache events
        #
        # @return [void]
        def subscribe_to_cache_events
          @subscriptions << ActiveSupport::Notifications.subscribe("cache.hit") do |name, start, finish, id, payload|
            log_cache_hit(payload)
          end

          @subscriptions << ActiveSupport::Notifications.subscribe("cache.miss") do |name, start, finish, id, payload|
            log_cache_miss(payload)
          end
        end

        # Log service started event
        #
        # @param payload [Hash] Event payload
        # @return [void]
        def log_service_started(payload)
          message = "[BetterService] #{payload[:service_name]} started"
          message += " (user: #{payload[:user_id]})" if payload[:user_id]

          log(message)
        end

        # Log service completed event
        #
        # @param payload [Hash] Event payload
        # @return [void]
        def log_service_completed(payload)
          message = "[BetterService] #{payload[:service_name]} completed in #{payload[:duration]}ms"
          message += " (user: #{payload[:user_id]})" if payload[:user_id]
          message += " [CACHED]" if payload[:cache_hit]

          log(message)
        end

        # Log service failed event
        #
        # @param payload [Hash] Event payload
        # @return [void]
        def log_service_failed(payload)
          message = "[BetterService] #{payload[:service_name]} failed after #{payload[:duration]}ms"
          message += " (user: #{payload[:user_id]})" if payload[:user_id]
          message += " - #{payload[:error_class]}: #{payload[:error_message]}"

          log(message, :error)
        end

        # Log cache hit event
        #
        # @param payload [Hash] Event payload
        # @return [void]
        def log_cache_hit(payload)
          message = "[BetterService::Cache] HIT - #{payload[:service_name]}"
          message += " (context: #{payload[:context]})" if payload[:context]

          log(message, :debug)
        end

        # Log cache miss event
        #
        # @param payload [Hash] Event payload
        # @return [void]
        def log_cache_miss(payload)
          message = "[BetterService::Cache] MISS - #{payload[:service_name]}"
          message += " (context: #{payload[:context]})" if payload[:context]

          log(message, :debug)
        end

        # Write to Rails logger
        #
        # @param message [String] Log message
        # @param level [Symbol] Log level (:debug, :info, :warn, :error)
        # @return [void]
        def log(message, level = nil)
          return unless defined?(Rails) && Rails.logger

          level ||= BetterService.configuration.log_subscriber_level
          Rails.logger.send(level, message)
        end
      end
    end
  end
end
