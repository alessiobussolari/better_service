# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe BetterService::Concerns::Instrumentation do
  before do
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

  after do
    # Unsubscribe from events
    @subscribers.each do |subscriber|
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
    @events.clear

    # Reset configuration
    BetterService.reset_configuration!
  end

  # Test Services for Testing
  class InstrumentationSimpleTestService < BetterService::Services::Base
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

  class InstrumentationFailingTestService < BetterService::Services::Base
    self._allow_nil_user = false

    schema do
      # Empty schema
    end

    private

    def respond(transformed_data)
      raise StandardError, "Intentional failure"
    end
  end

  class InstrumentationNilUserTestService < BetterService::Services::Base
    self._allow_nil_user = true

    schema do
      # Empty schema
    end

    private

    def respond(transformed_data)
      success_result("Nil user test")
    end
  end

  class InstrumentationSlowTestService < BetterService::Services::Base
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

  class InstrumentationCachedTestService < BetterService::Services::Base
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

  class InstrumentationValidationErrorTestService < BetterService::Services::Base
    self._allow_nil_user = false

    schema do
      required(:required_field).filled(:string)
    end

    private

    def respond(transformed_data)
      success_result("Should not reach here")
    end
  end

  describe "Basic Event Publishing" do
    it "service execution publishes service.started event" do
      service = InstrumentationSimpleTestService.new(@user, params: { name: "test" })
      service.call

      started_events = @events.select { |e| e[:name] == "service.started" }
      expect(started_events.size).to eq(1)

      event = started_events.first
      payload = event[:args][4]

      expect(payload[:service_name]).to end_with("InstrumentationSimpleTestService")
      expect(payload[:user_id]).to eq(123)
      expect(payload[:timestamp]).to be_present
    end

    it "service execution publishes service.completed event" do
      service = InstrumentationSimpleTestService.new(@user, params: { name: "test" })
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      expect(completed_events.size).to eq(1)

      event = completed_events.first
      payload = event[:args][4]

      expect(payload[:service_name]).to end_with("InstrumentationSimpleTestService")
      expect(payload[:user_id]).to eq(123)
      expect(payload[:duration]).to be > 0
      expect(payload[:success]).to be true
      expect(payload[:timestamp]).to be_present
    end

    it "service failure publishes service.failed event" do
      service = InstrumentationFailingTestService.new(@user, params: {})

      # With tuple format, errors return metadata instead of raising
      _object, meta = service.call
      expect(meta[:success]).to be false

      failed_events = @events.select { |e| e[:name] == "service.failed" }
      expect(failed_events.size).to eq(1)

      event = failed_events.first
      payload = event[:args][4]

      expect(payload[:service_name]).to end_with("InstrumentationFailingTestService")
      expect(payload[:user_id]).to eq(123)
      expect(payload[:duration]).to be > 0
      expect(payload[:success]).to be false
      expect(payload[:error_class]).to eq("execution_error")
      expect(payload[:error_message]).to match(/Intentional failure/)
    end
  end

  describe "Payload Content" do
    it "completed event includes params when configured" do
      BetterService.configure do |config|
        config.instrumentation_include_args = true
      end

      service = InstrumentationSimpleTestService.new(@user, params: { name: "test", value: 42 })
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      payload = completed_events.first[:args][4]

      expect(payload[:params]).to be_present
      expect(payload[:params][:name]).to eq("test")
      expect(payload[:params][:value]).to eq(42)
    end

    it "completed event excludes params when configured" do
      BetterService.configure do |config|
        config.instrumentation_include_args = false
      end

      service = InstrumentationSimpleTestService.new(@user, params: { name: "test" })
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      payload = completed_events.first[:args][4]

      expect(payload[:params]).to be_nil
    end

    it "completed event includes result when configured" do
      BetterService.configure do |config|
        config.instrumentation_include_result = true
      end

      service = InstrumentationSimpleTestService.new(@user, params: { name: "test" })
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      payload = completed_events.first[:args][4]

      expect(payload[:result]).to be_present
      # Result is now a BetterService::Result object
      expect(payload[:result]).to be_a(BetterService::Result)
      expect(payload[:result].success?).to be true
    end

    it "completed event excludes result when configured" do
      BetterService.configure do |config|
        config.instrumentation_include_result = false
      end

      service = InstrumentationSimpleTestService.new(@user, params: { name: "test" })
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      payload = completed_events.first[:args][4]

      expect(payload[:result]).to be_nil
    end
  end

  describe "Configuration" do
    it "instrumentation can be disabled globally" do
      BetterService.configure do |config|
        config.instrumentation_enabled = false
      end

      service = InstrumentationSimpleTestService.new(@user, params: { name: "test" })
      service.call

      # No events should be published
      expect(@events.size).to eq(0)
    end

    it "specific services can be excluded from instrumentation" do
      BetterService.configure do |config|
        config.instrumentation_excluded_services = ["InstrumentationSimpleTestService"]
      end

      service = InstrumentationSimpleTestService.new(@user, params: { name: "test" })
      service.call

      # No events should be published for excluded service
      expect(@events.size).to eq(0)
    end

    it "non-excluded services still publish events when others are excluded" do
      BetterService.configure do |config|
        config.instrumentation_excluded_services = ["OtherService"]
      end

      service = InstrumentationSimpleTestService.new(@user, params: { name: "test" })
      service.call

      # Events should be published for non-excluded service
      expect(@events.size).to be > 0
    end
  end

  describe "User ID Extraction" do
    it "extracts user_id from user object with id" do
      service = InstrumentationSimpleTestService.new(@user, params: {})
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      payload = completed_events.first[:args][4]

      expect(payload[:user_id]).to eq(123)
    end

    it "handles nil user gracefully" do
      # Create service that allows nil user
      service = InstrumentationNilUserTestService.new(nil, params: {})
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      payload = completed_events.first[:args][4]

      expect(payload[:user_id]).to be_nil
    end
  end

  describe "Duration Tracking" do
    it "tracks execution duration accurately" do
      service = InstrumentationSlowTestService.new(@user, params: {})
      service.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      payload = completed_events.first[:args][4]

      # Should take at least 10ms (we sleep 0.01)
      expect(payload[:duration]).to be >= 10
      expect(payload[:duration]).to be < 1000 # but not too long
    end

    it "tracks duration even on failure" do
      service = InstrumentationFailingTestService.new(@user, params: {})

      # With tuple format, errors return metadata instead of raising
      _object, meta = service.call
      expect(meta[:success]).to be false

      failed_events = @events.select { |e| e[:name] == "service.failed" }
      payload = failed_events.first[:args][4]

      expect(payload[:duration]).to be > 0
    end
  end

  describe "Cache Events" do
    it "cache miss event is published when cache is empty" do
      Rails.cache.clear

      service = InstrumentationCachedTestService.new(@user, params: { name: "test" })
      service.call

      cache_miss_events = @events.select { |e| e[:name] == "cache.miss" }
      expect(cache_miss_events.size).to eq(1)

      payload = cache_miss_events.first[:args][4]
      expect(payload[:service_name]).to end_with("InstrumentationCachedTestService")
      expect(payload[:event_type]).to eq("cache_miss")
      expect(payload[:cache_key]).to be_present
    end

    it "cache hit event is published when cache is populated" do
      Rails.cache.clear

      service1 = InstrumentationCachedTestService.new(@user, params: { name: "test" })
      service1.call

      # Clear events from first call
      @events.clear

      # Second call should hit cache
      service2 = InstrumentationCachedTestService.new(@user, params: { name: "test" })
      service2.call

      cache_hit_events = @events.select { |e| e[:name] == "cache.hit" }
      expect(cache_hit_events.size).to eq(1)

      payload = cache_hit_events.first[:args][4]
      expect(payload[:service_name]).to end_with("InstrumentationCachedTestService")
      expect(payload[:event_type]).to eq("cache_hit")
    end
  end

  describe "Error Handling" do
    it "instrumentation captures errors in metadata instead of raising" do
      service = InstrumentationFailingTestService.new(@user, params: {})

      # With tuple format, errors return metadata instead of raising
      _object, meta = service.call

      # Error details are in metadata
      expect(meta[:success]).to be false
      expect(meta[:error_code]).to eq(:execution_error)
      expect(meta[:message]).to match(/Intentional failure/)
    end

    it "instrumentation works with validation errors" do
      # Validation error is raised during initialization, not during call
      expect {
        service = InstrumentationValidationErrorTestService.new(@user, params: {})
        service.call
      }.to raise_error(BetterService::Errors::Runtime::ValidationError)

      # Validation errors happen before call method, so no service.failed event
      failed_events = @events.select { |e| e[:name] == "service.failed" }
      expect(failed_events.size).to eq(0)
    end
  end

  describe "Multiple Services" do
    it "multiple service calls publish separate events" do
      service1 = InstrumentationSimpleTestService.new(@user, params: { name: "first" })
      service1.call

      service2 = InstrumentationSimpleTestService.new(@user, params: { name: "second" })
      service2.call

      started_events = @events.select { |e| e[:name] == "service.started" }
      completed_events = @events.select { |e| e[:name] == "service.completed" }

      expect(started_events.size).to eq(2)
      expect(completed_events.size).to eq(2)
    end

    it "events from different service classes are distinguishable" do
      service1 = InstrumentationSimpleTestService.new(@user, params: {})
      service1.call

      service2 = InstrumentationSlowTestService.new(@user, params: {})
      service2.call

      completed_events = @events.select { |e| e[:name] == "service.completed" }
      service_names = completed_events.map { |e| e[:args][4][:service_name] }

      expect(service_names.any? { |name| name.end_with?("InstrumentationSimpleTestService") }).to be true
      expect(service_names.any? { |name| name.end_with?("InstrumentationSlowTestService") }).to be true
    end
  end
end
