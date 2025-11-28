# frozen_string_literal: true

module BetterService
  # Configuration - Centralized configuration for BetterService
  #
  # Provides configuration options for various BetterService features.
  #
  # @example Configure in initializer
  #   # config/initializers/better_service.rb
  #   BetterService.configure do |config|
  #     config.instrumentation_enabled = true
  #     config.instrumentation_include_args = false
  #     config.instrumentation_excluded_services = ["HealthCheckService"]
  #
  #     # Cache invalidation map for cascading cache invalidation
  #     config.cache_invalidation_map = {
  #       'products' => %w[products inventory reports],
  #       'orders' => %w[orders products reports],
  #       'users' => %w[users orders reports]
  #     }
  #   end
  class Configuration
    # Enable/disable instrumentation globally
    #
    # When disabled, no events will be published for any service.
    #
    # @return [Boolean] Default: true
    attr_accessor :instrumentation_enabled

    # Include service arguments in event payloads
    #
    # When enabled, args and kwargs are included in event payloads.
    # Disable if arguments contain sensitive data (passwords, tokens, etc.)
    #
    # @return [Boolean] Default: true
    attr_accessor :instrumentation_include_args

    # Include service result in event payloads
    #
    # When enabled, the service result is included in completion events.
    # Disable to reduce payload size or protect sensitive return values.
    #
    # @return [Boolean] Default: false
    attr_accessor :instrumentation_include_result

    # List of service class names to exclude from instrumentation
    #
    # Services in this list will not publish any events.
    # Useful for high-frequency services that would generate too many events.
    #
    # @return [Array<String>] Default: []
    attr_accessor :instrumentation_excluded_services

    # Enable/disable built-in log subscriber
    #
    # When enabled, all service events are logged to Rails.logger.
    #
    # @return [Boolean] Default: false
    attr_accessor :log_subscriber_enabled

    # Log level for built-in log subscriber
    #
    # Valid values: :debug, :info, :warn, :error
    #
    # @return [Symbol] Default: :info
    attr_accessor :log_subscriber_level

    # Enable/disable built-in stats subscriber
    #
    # When enabled, statistics are collected for all service executions.
    #
    # @return [Boolean] Default: false
    attr_accessor :stats_subscriber_enabled

    # Cache invalidation map for cascading cache invalidation
    #
    # When a context is invalidated, all related contexts in the map
    # are also invalidated automatically.
    #
    # @return [Hash<String, Array<String>>] Default: {}
    #
    # @example
    #   config.cache_invalidation_map = {
    #     'products' => %w[products inventory reports],
    #     'orders' => %w[orders products reports]
    #   }
    attr_reader :cache_invalidation_map

    # Set the cache invalidation map
    #
    # Automatically configures CacheService with the provided map.
    #
    # @param map [Hash<String, Array<String>>] Invalidation mappings
    # @return [void]
    def cache_invalidation_map=(map)
      @cache_invalidation_map = map
      CacheService.configure_invalidation_map(map) if map
    end

    def initialize
      # Instrumentation defaults
      @instrumentation_enabled = true
      @instrumentation_include_args = true
      @instrumentation_include_result = false
      @instrumentation_excluded_services = []

      # Built-in subscribers defaults
      @log_subscriber_enabled = false
      @log_subscriber_level = :info
      @stats_subscriber_enabled = false

      # Cache defaults
      @cache_invalidation_map = {}
    end
  end

  class << self
    # Get the global configuration object
    #
    # @return [BetterService::Configuration]
    def configuration
      @configuration ||= Configuration.new
    end

    # Configure BetterService
    #
    # @yield [Configuration] Configuration object
    # @return [void]
    #
    # @example
    #   BetterService.configure do |config|
    #     config.instrumentation_enabled = true
    #     config.log_subscriber_enabled = true
    #   end
    def configure
      yield(configuration)
    end

    # Reset configuration to defaults
    #
    # Useful for testing.
    #
    # @return [void]
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
