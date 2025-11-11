# frozen_string_literal: true

require "test_helper"
require "ostruct"

module BetterService
  class SubscribersTest < ActiveSupport::TestCase
    setup do
      # Reset configuration
      BetterService.reset_configuration!
      BetterService.configure do |config|
        config.instrumentation_enabled = true
        config.log_subscriber_enabled = true
        config.stats_subscriber_enabled = true
      end

      @user = OpenStruct.new(id: 456)

      # Reset and attach subscribers
      Subscribers::StatsSubscriber.reset!
      Subscribers::LogSubscriber.attach
      Subscribers::StatsSubscriber.attach
    end

    teardown do
      # Reset stats
      Subscribers::StatsSubscriber.reset!
      BetterService.reset_configuration!
    end

    # ========================================
    # Test Group: LogSubscriber
    # ========================================

    test "LogSubscriber logs service.started events" do
      log_output = capture_log_output do
        service = TestService.new(@user, params: {})
        service.call
      end

      assert_match(/BetterService/, log_output)
      assert_match(/TestService started/, log_output)
      assert_match(/user: 456/, log_output)
    end

    test "LogSubscriber logs service.completed events" do
      log_output = capture_log_output do
        service = TestService.new(@user, params: {})
        service.call
      end

      assert_match(/BetterService/, log_output)
      assert_match(/TestService completed/, log_output)
      assert_match(/\d+ms/, log_output)
      assert_match(/user: 456/, log_output)
    end

    test "LogSubscriber logs service.failed events with error level" do
      log_output = capture_log_output do
        service = FailingService.new(@user, params: {})
        begin
          service.call
        rescue StandardError
          # Expected
        end
      end

      assert_match(/BetterService/, log_output)
      assert_match(/FailingService failed/, log_output)
      assert_match(/StandardError/, log_output)
      assert_match(/Test error/, log_output)
    end

    test "LogSubscriber logs cache.hit events with debug level" do
      Rails.cache.clear

      # First call to populate cache
      service1 = CachedService.new(@user, params: { name: "test" })
      service1.call

      # Second call should hit cache
      log_output = capture_log_output do
        service2 = CachedService.new(@user, params: { name: "test" })
        service2.call
      end

      assert_match(/BetterService::Cache/, log_output)
      assert_match(/HIT/, log_output)
    end

    test "LogSubscriber logs cache.miss events with debug level" do
      Rails.cache.clear

      log_output = capture_log_output do
        service = CachedService.new(@user, params: { name: "test" })
        service.call
      end

      assert_match(/BetterService::Cache/, log_output)
      assert_match(/MISS/, log_output)
    end

    # ========================================
    # Test Group: StatsSubscriber - Basic Stats
    # ========================================

    test "StatsSubscriber tracks service executions" do
      service = TestService.new(@user, params: {})
      service.call

      # Get stats for first service (the full class name varies by test environment)
      service_name = Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("TestService") }
      stats = Subscribers::StatsSubscriber.stats_for(service_name)

      assert_not_nil stats
      assert_equal 1, stats[:executions]
      assert_equal 1, stats[:successes]
      assert_equal 0, stats[:failures]
    end

    test "StatsSubscriber tracks multiple executions" do
      3.times do
        service = TestService.new(@user, params: {})
        service.call
      end

      # Get stats for first service (the full class name varies by test environment)
      service_name = Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("TestService") }
      stats = Subscribers::StatsSubscriber.stats_for(service_name)

      assert_equal 3, stats[:executions]
      assert_equal 3, stats[:successes]
    end

    test "StatsSubscriber tracks failures" do
      begin
        service = FailingService.new(@user, params: {})
        service.call
      rescue StandardError
        # Expected
      end

      service_name = Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("FailingService") }
      stats = Subscribers::StatsSubscriber.stats_for(service_name)

      assert_equal 1, stats[:executions]
      assert_equal 0, stats[:successes]
      assert_equal 1, stats[:failures]
    end

    test "StatsSubscriber tracks error types" do
      begin
        service = FailingService.new(@user, params: {})
        service.call
      rescue StandardError
        # Expected
      end

      service_name = Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("FailingService") }
      stats = Subscribers::StatsSubscriber.stats_for(service_name)

      assert_equal 1, stats[:errors]["StandardError"]
    end

    test "StatsSubscriber tracks multiple error types" do
      # First error
      begin
        service = FailingService.new(@user, params: {})
        service.call
      rescue StandardError
        # Expected
      end

      # Second error of same type
      begin
        service = FailingService.new(@user, params: {})
        service.call
      rescue StandardError
        # Expected
      end

      service_name = Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("FailingService") }
      stats = Subscribers::StatsSubscriber.stats_for(service_name)

      assert_equal 2, stats[:errors]["StandardError"]
    end

    # ========================================
    # Test Group: StatsSubscriber - Duration
    # ========================================

    test "StatsSubscriber tracks total duration" do
      service = TestService.new(@user, params: {})
      service.call

      # Get stats for first service (the full class name varies by test environment)
      service_name = Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("TestService") }
      stats = Subscribers::StatsSubscriber.stats_for(service_name)

      assert stats[:total_duration] > 0
    end

    test "StatsSubscriber calculates average duration" do
      # Execute twice
      2.times do
        service = TestService.new(@user, params: {})
        service.call
      end

      # Get stats for first service (the full class name varies by test environment)
      service_name = Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("TestService") }
      stats = Subscribers::StatsSubscriber.stats_for(service_name)

      assert_equal 2, stats[:executions]
      assert stats[:avg_duration] > 0
      assert_equal (stats[:total_duration] / 2.0).round(2), stats[:avg_duration]
    end

    # ========================================
    # Test Group: StatsSubscriber - Cache Stats
    # ========================================

    test "StatsSubscriber tracks cache hits" do
      Rails.cache.clear

      # First call - cache miss
      service1 = CachedService.new(@user, params: { name: "test" })
      service1.call

      # Second call - cache hit
      service2 = CachedService.new(@user, params: { name: "test" })
      service2.call

      service_name = Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("CachedService") }
      stats = Subscribers::StatsSubscriber.stats_for(service_name)

      assert_equal 1, stats[:cache_hits]
    end

    test "StatsSubscriber tracks cache misses" do
      Rails.cache.clear

      service = CachedService.new(@user, params: { name: "test" })
      service.call

      service_name = Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("CachedService") }
      stats = Subscribers::StatsSubscriber.stats_for(service_name)

      assert_equal 1, stats[:cache_misses]
    end

    # ========================================
    # Test Group: StatsSubscriber - Summary
    # ========================================

    test "StatsSubscriber provides global summary" do
      # Execute multiple services
      service1 = TestService.new(@user, params: {})
      service1.call

      service2 = TestService.new(@user, params: {})
      service2.call

      begin
        service3 = FailingService.new(@user, params: {})
        service3.call
      rescue StandardError
        # Expected
      end

      summary = Subscribers::StatsSubscriber.summary

      assert_equal 2, summary[:total_services] # TestService and FailingService
      assert_equal 3, summary[:total_executions]
      assert_equal 2, summary[:total_successes]
      assert_equal 1, summary[:total_failures]
      assert_equal 66.67, summary[:success_rate]
      assert summary[:avg_duration] > 0
    end

    test "StatsSubscriber summary calculates cache hit rate" do
      Rails.cache.clear

      # First call - miss
      service1 = CachedService.new(@user, params: { name: "test" })
      service1.call

      # Second call - hit
      service2 = CachedService.new(@user, params: { name: "test" })
      service2.call

      summary = Subscribers::StatsSubscriber.summary

      assert_equal 50.0, summary[:cache_hit_rate]
    end

    # ========================================
    # Test Group: StatsSubscriber - Reset
    # ========================================

    test "StatsSubscriber can be reset" do
      service = TestService.new(@user, params: {})
      service.call

      assert Subscribers::StatsSubscriber.stats.size > 0

      Subscribers::StatsSubscriber.reset!

      assert_equal 0, Subscribers::StatsSubscriber.stats.size
    end

    # ========================================
    # Test Group: Multiple Services
    # ========================================

    test "StatsSubscriber tracks different services separately" do
      service1 = TestService.new(@user, params: {})
      service1.call

      begin
        service2 = FailingService.new(@user, params: {})
        service2.call
      rescue StandardError
        # Expected
      end

      test_service_name = Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("TestService") && !k.include?("Failing") }
      failing_service_name = Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("FailingService") }

      test_stats = Subscribers::StatsSubscriber.stats_for(test_service_name)
      failing_stats = Subscribers::StatsSubscriber.stats_for(failing_service_name)

      assert_equal 1, test_stats[:executions]
      assert_equal 1, test_stats[:successes]

      assert_equal 1, failing_stats[:executions]
      assert_equal 1, failing_stats[:failures]
    end

    # ========================================
    # Test Services
    # ========================================

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

    class FailingService < BetterService::Services::Base
      self._allow_nil_user = false

      schema do
        # Empty schema
      end

      private

      def respond(transformed_data)
        raise StandardError, "Test error"
      end
    end

    class CachedService < BetterService::Services::Base
      self._allow_nil_user = false

      cache_key "subscribers_test_cache"
      cache_ttl 60

      schema do
        optional(:name).filled(:string)
      end

      private

      def respond(transformed_data)
        success_result("Cached result")
      end
    end

    private

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
  end
end
