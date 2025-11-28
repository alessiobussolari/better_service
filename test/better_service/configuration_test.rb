# frozen_string_literal: true

require "test_helper"

module BetterService
  class ConfigurationTest < ActiveSupport::TestCase
    def setup
      # Reset configuration before each test
      BetterService.reset_configuration!
    end

    def teardown
      # Reset configuration after each test
      BetterService.reset_configuration!
    end

    # ========================================
    # Default Values Tests
    # ========================================

    test "Configuration has default instrumentation_enabled true" do
      config = Configuration.new
      assert config.instrumentation_enabled
    end

    test "Configuration has default instrumentation_include_args true" do
      config = Configuration.new
      assert config.instrumentation_include_args
    end

    test "Configuration has default instrumentation_include_result false" do
      config = Configuration.new
      refute config.instrumentation_include_result
    end

    test "Configuration has default instrumentation_excluded_services empty array" do
      config = Configuration.new
      assert_equal [], config.instrumentation_excluded_services
    end

    test "Configuration has default log_subscriber_enabled false" do
      config = Configuration.new
      refute config.log_subscriber_enabled
    end

    test "Configuration has default log_subscriber_level info" do
      config = Configuration.new
      assert_equal :info, config.log_subscriber_level
    end

    test "Configuration has default stats_subscriber_enabled false" do
      config = Configuration.new
      refute config.stats_subscriber_enabled
    end

    test "Configuration has default cache_invalidation_map empty hash" do
      config = Configuration.new
      assert_equal({}, config.cache_invalidation_map)
    end

    # ========================================
    # Configuration Setter Tests
    # ========================================

    test "Configuration allows setting instrumentation_enabled" do
      config = Configuration.new
      config.instrumentation_enabled = false
      refute config.instrumentation_enabled
    end

    test "Configuration allows setting instrumentation_include_args" do
      config = Configuration.new
      config.instrumentation_include_args = false
      refute config.instrumentation_include_args
    end

    test "Configuration allows setting instrumentation_include_result" do
      config = Configuration.new
      config.instrumentation_include_result = true
      assert config.instrumentation_include_result
    end

    test "Configuration allows setting instrumentation_excluded_services" do
      config = Configuration.new
      config.instrumentation_excluded_services = ["HealthCheckService", "PingService"]
      assert_equal ["HealthCheckService", "PingService"], config.instrumentation_excluded_services
    end

    test "Configuration allows setting log_subscriber_enabled" do
      config = Configuration.new
      config.log_subscriber_enabled = true
      assert config.log_subscriber_enabled
    end

    test "Configuration allows setting log_subscriber_level" do
      config = Configuration.new
      config.log_subscriber_level = :debug
      assert_equal :debug, config.log_subscriber_level
    end

    test "Configuration allows setting stats_subscriber_enabled" do
      config = Configuration.new
      config.stats_subscriber_enabled = true
      assert config.stats_subscriber_enabled
    end

    # ========================================
    # BetterService Module Methods Tests
    # ========================================

    test "BetterService.configuration returns Configuration instance" do
      assert_instance_of Configuration, BetterService.configuration
    end

    test "BetterService.configuration returns same instance on multiple calls" do
      config1 = BetterService.configuration
      config2 = BetterService.configuration
      assert_same config1, config2
    end

    test "BetterService.configure yields configuration object" do
      yielded_config = nil

      BetterService.configure do |config|
        yielded_config = config
      end

      assert_same BetterService.configuration, yielded_config
    end

    test "BetterService.configure allows setting options" do
      BetterService.configure do |config|
        config.instrumentation_enabled = false
        config.log_subscriber_enabled = true
        config.log_subscriber_level = :warn
      end

      config = BetterService.configuration
      refute config.instrumentation_enabled
      assert config.log_subscriber_enabled
      assert_equal :warn, config.log_subscriber_level
    end

    test "BetterService.reset_configuration! creates new instance" do
      original_config = BetterService.configuration
      original_config.instrumentation_enabled = false

      BetterService.reset_configuration!

      new_config = BetterService.configuration
      refute_same original_config, new_config
      assert new_config.instrumentation_enabled # Reset to default
    end

    # ========================================
    # Cache Invalidation Map Tests
    # ========================================

    test "cache_invalidation_map setter stores the map" do
      config = Configuration.new
      map = { "products" => %w[products inventory], "orders" => %w[orders products] }

      config.cache_invalidation_map = map

      assert_equal map, config.cache_invalidation_map
    end

    test "cache_invalidation_map setter configures CacheService" do
      # Save original map
      original_map = CacheService.instance_variable_get(:@invalidation_map) || {}

      begin
        # Reset CacheService invalidation map first
        CacheService.configure_invalidation_map({})

        map = { "test_context" => %w[test_context related_context] }
        config = Configuration.new
        config.cache_invalidation_map = map

        # Verify CacheService received the map
        assert_equal map, CacheService.instance_variable_get(:@invalidation_map)
      ensure
        # Restore original map to avoid affecting other tests
        CacheService.configure_invalidation_map(original_map)
      end
    end

    test "cache_invalidation_map setter handles nil gracefully" do
      config = Configuration.new
      config.cache_invalidation_map = nil

      assert_nil config.cache_invalidation_map
    end

    # ========================================
    # Integration Tests
    # ========================================

    test "full configuration flow works correctly" do
      BetterService.reset_configuration!

      BetterService.configure do |config|
        config.instrumentation_enabled = true
        config.instrumentation_include_args = false
        config.instrumentation_include_result = true
        config.instrumentation_excluded_services = ["HealthCheckService"]
        config.log_subscriber_enabled = true
        config.log_subscriber_level = :debug
        config.stats_subscriber_enabled = true
      end

      config = BetterService.configuration

      assert config.instrumentation_enabled
      refute config.instrumentation_include_args
      assert config.instrumentation_include_result
      assert_equal ["HealthCheckService"], config.instrumentation_excluded_services
      assert config.log_subscriber_enabled
      assert_equal :debug, config.log_subscriber_level
      assert config.stats_subscriber_enabled
    end
  end
end
