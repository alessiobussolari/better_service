# frozen_string_literal: true

module BetterService
  module Subscribers
    # StatsSubscriber - Built-in subscriber that collects service statistics
    #
    # This subscriber tracks execution metrics for all services:
    # - Total executions
    # - Success/failure counts
    # - Average duration
    # - Cache hit rate
    #
    # @example Enable in initializer
    #   BetterService.configure do |config|
    #     config.stats_subscriber_enabled = true
    #   end
    #
    # @example Access statistics
    #   BetterService::Subscribers::StatsSubscriber.stats
    #   # => {
    #   #   "ProductsIndexService" => {
    #   #     executions: 150,
    #   #     successes: 148,
    #   #     failures: 2,
    #   #     total_duration: 4500.0,
    #   #     avg_duration: 30.0,
    #   #     cache_hits: 120,
    #   #     cache_misses: 30
    #   #   }
    #   # }
    class StatsSubscriber
      class << self
        # Storage for service statistics
        #
        # @return [Hash] Statistics hash
        attr_reader :stats

        # Storage for ActiveSupport::Notifications subscriptions
        #
        # @return [Array<ActiveSupport::Notifications::Fanout::Subscriber>]
        attr_reader :subscriptions

        # Attach the subscriber to ActiveSupport::Notifications
        #
        # This method is called automatically when subscriber is enabled.
        #
        # @return [void]
        def attach
          reset!
          @subscriptions ||= []
          subscribe_to_service_events
          subscribe_to_cache_events
        end

        # Reset all statistics
        #
        # Useful for testing or periodic reset in production.
        #
        # @return [void]
        def reset!
          # Unsubscribe from all existing subscriptions
          if @subscriptions
            @subscriptions.each do |subscription|
              ActiveSupport::Notifications.unsubscribe(subscription)
            end
          end
          @subscriptions = []
          @stats = {}
        end

        # Get statistics for a specific service
        #
        # @param service_name [String] Name of service class
        # @return [Hash, nil] Service statistics or nil if not found
        def stats_for(service_name)
          @stats[service_name]
        end

        # Get statistics summary across all services
        #
        # @return [Hash] Aggregated statistics
        def summary
          total_executions = @stats.values.sum { |s| s[:executions] }
          total_successes = @stats.values.sum { |s| s[:successes] }
          total_failures = @stats.values.sum { |s| s[:failures] }
          total_duration = @stats.values.sum { |s| s[:total_duration] }
          total_cache_hits = @stats.values.sum { |s| s[:cache_hits] }
          total_cache_misses = @stats.values.sum { |s| s[:cache_misses] }

          {
            total_services: @stats.keys.size,
            total_executions: total_executions,
            total_successes: total_successes,
            total_failures: total_failures,
            success_rate: total_executions > 0 ? (total_successes.to_f / total_executions * 100).round(2) : 0,
            avg_duration: total_executions > 0 ? (total_duration / total_executions).round(2) : 0,
            cache_hit_rate: (total_cache_hits + total_cache_misses) > 0 ? (total_cache_hits.to_f / (total_cache_hits + total_cache_misses) * 100).round(2) : 0
          }
        end

        private

        # Subscribe to service lifecycle events
        #
        # @return [void]
        def subscribe_to_service_events
          @subscriptions << ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
            record_completion(payload)
          end

          @subscriptions << ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
            record_failure(payload)
          end
        end

        # Subscribe to cache events
        #
        # @return [void]
        def subscribe_to_cache_events
          @subscriptions << ActiveSupport::Notifications.subscribe("cache.hit") do |name, start, finish, id, payload|
            record_cache_hit(payload)
          end

          @subscriptions << ActiveSupport::Notifications.subscribe("cache.miss") do |name, start, finish, id, payload|
            record_cache_miss(payload)
          end
        end

        # Record service completion
        #
        # @param payload [Hash] Event payload
        # @return [void]
        def record_completion(payload)
          service_name = payload[:service_name]
          ensure_service_stats(service_name)

          @stats[service_name][:executions] += 1
          @stats[service_name][:successes] += 1
          @stats[service_name][:total_duration] += payload[:duration]
          @stats[service_name][:avg_duration] = (@stats[service_name][:total_duration] / @stats[service_name][:executions]).round(2)

          # Record cache hit if present
          if payload[:cache_hit]
            @stats[service_name][:cache_hits] += 1
          end
        end

        # Record service failure
        #
        # @param payload [Hash] Event payload
        # @return [void]
        def record_failure(payload)
          service_name = payload[:service_name]
          ensure_service_stats(service_name)

          @stats[service_name][:executions] += 1
          @stats[service_name][:failures] += 1
          @stats[service_name][:total_duration] += payload[:duration]
          @stats[service_name][:avg_duration] = (@stats[service_name][:total_duration] / @stats[service_name][:executions]).round(2)

          # Track error types
          error_class = payload[:error_class]
          @stats[service_name][:errors][error_class] ||= 0
          @stats[service_name][:errors][error_class] += 1
        end

        # Record cache hit
        #
        # @param payload [Hash] Event payload
        # @return [void]
        def record_cache_hit(payload)
          service_name = payload[:service_name]
          ensure_service_stats(service_name)

          @stats[service_name][:cache_hits] += 1
        end

        # Record cache miss
        #
        # @param payload [Hash] Event payload
        # @return [void]
        def record_cache_miss(payload)
          service_name = payload[:service_name]
          ensure_service_stats(service_name)

          @stats[service_name][:cache_misses] += 1
        end

        # Ensure service has stats entry
        #
        # @param service_name [String] Name of service class
        # @return [void]
        def ensure_service_stats(service_name)
          @stats[service_name] ||= {
            executions: 0,
            successes: 0,
            failures: 0,
            total_duration: 0.0,
            avg_duration: 0.0,
            cache_hits: 0,
            cache_misses: 0,
            errors: {}
          }
        end
      end
    end
  end
end
