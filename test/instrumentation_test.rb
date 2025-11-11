# frozen_string_literal: true

require "test_helper"
require "ostruct"

module BetterService
  class InstrumentationTest < ActiveSupport::TestCase
    setup do
      # Reset configuration before each test
      BetterService.reset_configuration!
      BetterService.configure do |config|
        config.instrumentation_enabled = true
        config.instrumentation_include_args = true
        config.instrumentation_include_result = false
      end

      @user = OpenStruct.new(id: 123)
      @events = []

      # Subscribe to all events and capture them
      @subscribers = []
      @subscribers << ActiveSupport::Notifications.subscribe("service.started") do |*args|
        @events << { name: "service.started", args: args }
      end
      @subscribers << ActiveSupport::Notifications.subscribe("service.completed") do |*args|
        @events << { name: "service.completed", args: args }
      end
      @subscribers << ActiveSupport::Notifications.subscribe("service.failed") do |*args|
        @events << { name: "service.failed", args: args }
      end
      @subscribers << ActiveSupport::Notifications.subscribe("cache.hit") do |*args|
        @events << { name: "cache.hit", args: args }
      end
      @subscribers << ActiveSupport::Notifications.subscribe("cache.miss") do |*args|
        @events << { name: "cache.miss", args: args }
      end
    end

    teardown do
      # Unsubscribe from events
      @subscribers.each do |subscriber|
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
      @events.clear

      # Reset configuration
      BetterService.reset_configuration!
    end

    # ========================================
    # Test Group: Basic Event Publishing
    # ========================================

    test "service execution publishes service.started event" do
      service = SimpleTestService.new(@user, params: { name: "test" })
      service.call

      started_events = @events.select { |e| e[:name] == "service.started" }
      assert_equal 1, started_events.size

      event = started_events.first
      payload = event[:args][4]

      assert payload[:service_name].end_with?("SimpleTestService")
      assert_equal 123, payload[:user_id]
      assert payload[:timestamp].present?
    end

    test "service execution publishes service.completed event" do
      service = SimpleTestService.new(@user, params: { name: "test" })
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      assert_equal 1, completed_events.size

      event = completed_events.first
      payload = event[:args][4]

      assert payload[:service_name].end_with?("SimpleTestService")
      assert_equal 123, payload[:user_id]
      assert payload[:duration] > 0
      assert_equal true, payload[:success]
      assert payload[:timestamp].present?
    end

    test "service failure publishes service.failed event" do
      service = FailingTestService.new(@user, params: {})

      assert_raises(StandardError) do
        service.call
      end

      failed_events = @events.select { |e| e[:name] == "service.failed" }
      assert_equal 1, failed_events.size

      event = failed_events.first
      payload = event[:args][4]

      assert payload[:service_name].end_with?("FailingTestService")
      assert_equal 123, payload[:user_id]
      assert payload[:duration] > 0
      assert_equal false, payload[:success]
      assert_equal "StandardError", payload[:error_class]
      assert_equal "Intentional failure", payload[:error_message]
      assert payload[:error_backtrace].present?
    end

    # ========================================
    # Test Group: Payload Content
    # ========================================

    test "completed event includes params when configured" do
      BetterService.configure do |config|
        config.instrumentation_include_args = true
      end

      service = SimpleTestService.new(@user, params: { name: "test", value: 42 })
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      payload = completed_events.first[:args][4]

      assert payload[:params].present?
      assert_equal "test", payload[:params][:name]
      assert_equal 42, payload[:params][:value]
    end

    test "completed event excludes params when configured" do
      BetterService.configure do |config|
        config.instrumentation_include_args = false
      end

      service = SimpleTestService.new(@user, params: { name: "test" })
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      payload = completed_events.first[:args][4]

      assert_nil payload[:params]
    end

    test "completed event includes result when configured" do
      BetterService.configure do |config|
        config.instrumentation_include_result = true
      end

      service = SimpleTestService.new(@user, params: { name: "test" })
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      payload = completed_events.first[:args][4]

      assert payload[:result].present?
      assert payload[:result].is_a?(Hash)
    end

    test "completed event excludes result when configured" do
      BetterService.configure do |config|
        config.instrumentation_include_result = false
      end

      service = SimpleTestService.new(@user, params: { name: "test" })
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      payload = completed_events.first[:args][4]

      assert_nil payload[:result]
    end

    # ========================================
    # Test Group: Configuration
    # ========================================

    test "instrumentation can be disabled globally" do
      BetterService.configure do |config|
        config.instrumentation_enabled = false
      end

      service = SimpleTestService.new(@user, params: { name: "test" })
      service.call

      # No events should be published
      assert_equal 0, @events.size
    end

    test "specific services can be excluded from instrumentation" do
      BetterService.configure do |config|
        config.instrumentation_excluded_services = ["SimpleTestService"]
      end

      service = SimpleTestService.new(@user, params: { name: "test" })
      service.call

      # No events should be published for excluded service
      assert_equal 0, @events.size
    end

    test "non-excluded services still publish events when others are excluded" do
      BetterService.configure do |config|
        config.instrumentation_excluded_services = ["OtherService"]
      end

      service = SimpleTestService.new(@user, params: { name: "test" })
      service.call

      # Events should be published for non-excluded service
      assert @events.size > 0
    end

    # ========================================
    # Test Group: User ID Extraction
    # ========================================

    test "extracts user_id from user object with id" do
      service = SimpleTestService.new(@user, params: {})
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      payload = completed_events.first[:args][4]

      assert_equal 123, payload[:user_id]
    end

    test "handles nil user gracefully" do
      # Create service that allows nil user
      service = NilUserTestService.new(nil, params: {})
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      payload = completed_events.first[:args][4]

      assert_nil payload[:user_id]
    end

    # ========================================
    # Test Group: Duration Tracking
    # ========================================

    test "tracks execution duration accurately" do
      service = SlowTestService.new(@user, params: {})
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      payload = completed_events.first[:args][4]

      # Should take at least 10ms (we sleep 0.01)
      assert payload[:duration] >= 10
      assert payload[:duration] < 1000 # but not too long
    end

    test "tracks duration even on failure" do
      service = FailingTestService.new(@user, params: {})

      assert_raises(StandardError) do
        service.call
      end

      failed_events = @events.select { |e| e[:name] == "service.failed" }
      payload = failed_events.first[:args][4]

      assert payload[:duration] > 0
    end

    # ========================================
    # Test Group: Cache Events
    # ========================================

    test "cache miss event is published when cache is empty" do
      Rails.cache.clear

      service = CachedTestService.new(@user, params: { name: "test" })
      service.call

      cache_miss_events = @events.select { |e| e[:name] == "cache.miss" }
      assert_equal 1, cache_miss_events.size

      payload = cache_miss_events.first[:args][4]
      assert payload[:service_name].end_with?("CachedTestService")
      assert_equal "cache_miss", payload[:event_type]
      assert payload[:cache_key].present?
    end

    test "cache hit event is published when cache is populated" do
      Rails.cache.clear

      service1 = CachedTestService.new(@user, params: { name: "test" })
      service1.call

      # Clear events from first call
      @events.clear

      # Second call should hit cache
      service2 = CachedTestService.new(@user, params: { name: "test" })
      service2.call

      cache_hit_events = @events.select { |e| e[:name] == "cache.hit" }
      assert_equal 1, cache_hit_events.size

      payload = cache_hit_events.first[:args][4]
      assert payload[:service_name].end_with?("CachedTestService")
      assert_equal "cache_hit", payload[:event_type]
    end

    # ========================================
    # Test Group: Error Handling
    # ========================================

    test "instrumentation does not swallow exceptions" do
      service = FailingTestService.new(@user, params: {})

      error = assert_raises(BetterService::Errors::Runtime::ExecutionError) do
        service.call
      end

      # Error is wrapped in ExecutionError with context
      assert_equal "Service execution failed: Intentional failure", error.message
      assert_equal BetterService::ErrorCodes::EXECUTION_ERROR, error.code
      assert error.original_error.is_a?(StandardError)
      assert_equal "Intentional failure", error.original_error.message
    end

    test "instrumentation works with validation errors" do
      # Validation error is raised during initialization, not during call
      assert_raises(BetterService::Errors::Runtime::ValidationError) do
        service = ValidationErrorTestService.new(@user, params: {})
        service.call
      end

      # Validation errors happen before call method, so no service.failed event
      failed_events = @events.select { |e| e[:name] == "service.failed" }
      assert_equal 0, failed_events.size
    end

    # ========================================
    # Test Group: Multiple Services
    # ========================================

    test "multiple service calls publish separate events" do
      service1 = SimpleTestService.new(@user, params: { name: "first" })
      service1.call

      service2 = SimpleTestService.new(@user, params: { name: "second" })
      service2.call

      started_events = @events.select { |e| e[:name] == "service.started" }
      completed_events = @events.select { |e| e[:name] == "service.completed" }

      assert_equal 2, started_events.size
      assert_equal 2, completed_events.size
    end

    test "events from different service classes are distinguishable" do
      service1 = SimpleTestService.new(@user, params: {})
      service1.call

      service2 = SlowTestService.new(@user, params: {})
      service2.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      service_names = completed_events.map { |e| e[:args][4][:service_name] }

      assert service_names.any? { |name| name.end_with?("SimpleTestService") }
      assert service_names.any? { |name| name.end_with?("SlowTestService") }
    end

    # ========================================
    # Test Services for Testing
    # ========================================

    class SimpleTestService < BetterService::Services::Base
      self._allow_nil_user = false

      schema do
        optional(:name).filled(:string)
        optional(:value).filled(:integer)
      end

      private

      def respond(transformed_data)
        success_result("Test completed", data: { name: params[:name] })
      end
    end

    class FailingTestService < BetterService::Services::Base
      self._allow_nil_user = false

      schema do
        # Empty schema
      end

      private

      def respond(transformed_data)
        raise StandardError, "Intentional failure"
      end
    end

    class NilUserTestService < BetterService::Services::Base
      self._allow_nil_user = true

      schema do
        # Empty schema
      end

      private

      def respond(transformed_data)
        success_result("Nil user test")
      end
    end

    class SlowTestService < BetterService::Services::Base
      self._allow_nil_user = false

      schema do
        # Empty schema
      end

      private

      def respond(transformed_data)
        sleep 0.01 # 10ms
        success_result("Slow test completed")
      end
    end

    class CachedTestService < BetterService::Services::Base
      self._allow_nil_user = false

      cache_key "cached_test"
      cache_ttl 60

      schema do
        optional(:name).filled(:string)
      end

      private

      def respond(transformed_data)
        success_result("Cached test", data: { name: params[:name] })
      end
    end

    class ValidationErrorTestService < BetterService::Services::Base
      self._allow_nil_user = false

      schema do
        required(:required_field).filled(:string)
      end

      private

      def respond(transformed_data)
        success_result("Should not reach here")
      end
    end
  end
end
