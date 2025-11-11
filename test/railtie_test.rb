# frozen_string_literal: true

require "test_helper"

module BetterService
  # RailtieTest - Tests for automatic subscriber initialization
  #
  # These tests verify that the Railtie correctly initializes subscribers
  # based on configuration settings when Rails boots.
  class RailtieTest < ActiveSupport::TestCase
    setup do
      # Reset configuration before each test
      BetterService.reset_configuration!

      # Detach and reset subscribers to ensure clean state
      Subscribers::LogSubscriber.detach
      Subscribers::StatsSubscriber.reset!
    end

    teardown do
      # Reset after each test
      BetterService.reset_configuration!
      Subscribers::LogSubscriber.detach
      Subscribers::StatsSubscriber.reset!
    end

    # ========================================
    # Test Group: LogSubscriber Initialization
    # ========================================

    test "activates LogSubscriber when log_subscriber_enabled is true" do
      # Configure to enable LogSubscriber
      BetterService.configure do |config|
        config.log_subscriber_enabled = true
        config.stats_subscriber_enabled = false
      end

      # Simulate the Railtie's after_initialize block
      simulate_railtie_initialization

      # Verify that LogSubscriber received events
      log_output = capture_log_output do
        TestService.new(test_user, params: {}).call
      end

      assert_match(/BetterService/, log_output)
      assert_match(/TestService/, log_output)
    end

    test "does not activate LogSubscriber when log_subscriber_enabled is false" do
      # Configure to disable LogSubscriber
      BetterService.configure do |config|
        config.log_subscriber_enabled = false
        config.stats_subscriber_enabled = false
      end

      # Simulate the Railtie's after_initialize block
      simulate_railtie_initialization

      # Verify that no log output is generated
      log_output = capture_log_output do
        TestService.new(test_user, params: {}).call
      end

      # Should not contain BetterService logs (only regular Rails logs)
      assert_no_match(/\[BetterService\].*TestService/, log_output)
    end

    # ========================================
    # Test Group: StatsSubscriber Initialization
    # ========================================

    test "activates StatsSubscriber when stats_subscriber_enabled is true" do
      # Configure to enable StatsSubscriber
      BetterService.configure do |config|
        config.log_subscriber_enabled = false
        config.stats_subscriber_enabled = true
        config.instrumentation_enabled = true
      end

      # Simulate the Railtie's after_initialize block
      simulate_railtie_initialization

      # Execute a service
      TestService.new(test_user, params: {}).call

      # Verify that stats were collected
      stats = Subscribers::StatsSubscriber.stats
      assert stats.any?, "StatsSubscriber should have collected stats"

      service_name = stats.keys.find { |k| k.include?("TestService") }
      assert_not_nil service_name, "Should have stats for TestService"
      assert_equal 1, stats[service_name][:executions]
    end

    test "does not activate StatsSubscriber when stats_subscriber_enabled is false" do
      # Configure to disable StatsSubscriber
      BetterService.configure do |config|
        config.log_subscriber_enabled = false
        config.stats_subscriber_enabled = false
        config.instrumentation_enabled = true
      end

      # Simulate the Railtie's after_initialize block
      simulate_railtie_initialization

      # Execute a service
      TestService.new(test_user, params: {}).call

      # Verify that NO stats were collected
      stats = Subscribers::StatsSubscriber.stats
      assert_equal 0, stats.size, "StatsSubscriber should not have collected stats"
    end

    # ========================================
    # Test Group: Combined Initialization
    # ========================================

    test "activates both subscribers when both are enabled" do
      # Configure to enable both
      BetterService.configure do |config|
        config.log_subscriber_enabled = true
        config.stats_subscriber_enabled = true
        config.instrumentation_enabled = true
      end

      # Simulate the Railtie's after_initialize block
      simulate_railtie_initialization

      # Execute a service
      log_output = capture_log_output do
        TestService.new(test_user, params: {}).call
      end

      # Verify LogSubscriber is active
      assert_match(/BetterService/, log_output)
      assert_match(/TestService/, log_output)

      # Verify StatsSubscriber is active
      stats = Subscribers::StatsSubscriber.stats
      assert stats.any?, "StatsSubscriber should be active"
    end

    test "activates only LogSubscriber when only log_subscriber_enabled is true" do
      # Configure to enable only LogSubscriber
      BetterService.configure do |config|
        config.log_subscriber_enabled = true
        config.stats_subscriber_enabled = false
        config.instrumentation_enabled = true
      end

      # Simulate the Railtie's after_initialize block
      simulate_railtie_initialization

      # Execute a service
      log_output = capture_log_output do
        TestService.new(test_user, params: {}).call
      end

      # Verify LogSubscriber is active
      assert_match(/BetterService/, log_output)

      # Verify StatsSubscriber is NOT active
      stats = Subscribers::StatsSubscriber.stats
      assert_equal 0, stats.size, "StatsSubscriber should not be active"
    end

    test "activates only StatsSubscriber when only stats_subscriber_enabled is true" do
      # Configure to enable only StatsSubscriber
      BetterService.configure do |config|
        config.log_subscriber_enabled = false
        config.stats_subscriber_enabled = true
        config.instrumentation_enabled = true
      end

      # Simulate the Railtie's after_initialize block
      simulate_railtie_initialization

      # Execute a service
      log_output = capture_log_output do
        TestService.new(test_user, params: {}).call
      end

      # Verify LogSubscriber is NOT active
      assert_no_match(/\[BetterService\].*TestService/, log_output)

      # Verify StatsSubscriber is active
      stats = Subscribers::StatsSubscriber.stats
      assert stats.any?, "StatsSubscriber should be active"
    end

    # ========================================
    # Test Group: Initialization Logging
    # ========================================

    test "logs confirmation message when LogSubscriber is attached" do
      BetterService.configure do |config|
        config.log_subscriber_enabled = true
      end

      log_output = capture_log_output do
        simulate_railtie_initialization
      end

      assert_match(/\[BetterService\] LogSubscriber attached/, log_output)
    end

    test "logs confirmation message when StatsSubscriber is attached" do
      BetterService.configure do |config|
        config.stats_subscriber_enabled = true
      end

      log_output = capture_log_output do
        simulate_railtie_initialization
      end

      assert_match(/\[BetterService\] StatsSubscriber attached/, log_output)
    end

    test "logs both confirmation messages when both subscribers are attached" do
      BetterService.configure do |config|
        config.log_subscriber_enabled = true
        config.stats_subscriber_enabled = true
      end

      log_output = capture_log_output do
        simulate_railtie_initialization
      end

      assert_match(/\[BetterService\] LogSubscriber attached/, log_output)
      assert_match(/\[BetterService\] StatsSubscriber attached/, log_output)
    end

    test "does not log confirmation when subscribers are disabled" do
      BetterService.configure do |config|
        config.log_subscriber_enabled = false
        config.stats_subscriber_enabled = false
      end

      log_output = capture_log_output do
        simulate_railtie_initialization
      end

      assert_no_match(/\[BetterService\].*Subscriber attached/, log_output)
    end

    # ========================================
    # Helper Methods
    # ========================================

    private

    # Simulate the Railtie's after_initialize block
    #
    # This manually executes the same logic that the Railtie runs
    # when Rails boots, allowing us to test it in isolation.
    def simulate_railtie_initialization
      # Attach LogSubscriber if enabled in configuration
      if BetterService.configuration.log_subscriber_enabled
        BetterService::Subscribers::LogSubscriber.attach
        Rails.logger.info "[BetterService] LogSubscriber attached" if Rails.logger
      end

      # Attach StatsSubscriber if enabled in configuration
      if BetterService.configuration.stats_subscriber_enabled
        BetterService::Subscribers::StatsSubscriber.attach
        Rails.logger.info "[BetterService] StatsSubscriber attached" if Rails.logger
      end
    end

    # Capture log output for assertions
    #
    # @return [String] Captured log output
    def capture_log_output
      return "" unless defined?(Rails) && Rails.logger

      original_logger = Rails.logger
      log_output = StringIO.new
      Rails.logger = Logger.new(log_output)

      yield

      log_output.string
    ensure
      Rails.logger = original_logger if original_logger
    end

    # Create a test user for service initialization
    #
    # @return [OpenStruct] Test user object
    def test_user
      require "ostruct"
      OpenStruct.new(id: 123)
    end

    # ========================================
    # Test Service Classes
    # ========================================

    # Simple test service for testing initialization
    class TestService < BetterService::Services::Base
      self._allow_nil_user = false

      schema do
        # Empty schema
      end

      private

      def respond(transformed_data)
        success_result("Test completed")
      end
    end
  end
end
