# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe "Subscribers" do
  let(:user) { OpenStruct.new(id: 456) }

  before do
    # Reset configuration
    BetterService.reset_configuration!
    BetterService.configure do |config|
      config.instrumentation_enabled = true
      config.log_subscriber_enabled = true
      config.stats_subscriber_enabled = true
    end

    # Detach any existing subscribers and reset stats
    BetterService::Subscribers::LogSubscriber.detach
    BetterService::Subscribers::StatsSubscriber.reset!

    # Attach subscribers fresh for this test
    BetterService::Subscribers::LogSubscriber.attach
    BetterService::Subscribers::StatsSubscriber.attach
  end

  after do
    # Detach subscribers and reset
    BetterService::Subscribers::LogSubscriber.detach
    BetterService::Subscribers::StatsSubscriber.reset!
    BetterService.reset_configuration!
  end

  # Test Services
  class SubscribersTestService < BetterService::Services::Base
    self._allow_nil_user = false

    schema do
      # Empty schema
    end

    private

    def respond(transformed_data)
      success_result("Test completed")
    end
  end

  class SubscribersFailingService < BetterService::Services::Base
    self._allow_nil_user = false

    schema do
      # Empty schema
    end

    private

    def respond(transformed_data)
      raise StandardError, "Test error"
    end
  end

  class SubscribersCachedService < BetterService::Services::Base
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

  describe BetterService::Subscribers::LogSubscriber do
    it "logs service.started events" do
      log_output = capture_log_output do
        service = SubscribersTestService.new(user, params: {})
        service.call
      end

      expect(log_output).to match(/BetterService/)
      expect(log_output).to match(/SubscribersTestService started/)
      expect(log_output).to match(/user: 456/)
    end

    it "logs service.completed events" do
      log_output = capture_log_output do
        service = SubscribersTestService.new(user, params: {})
        service.call
      end

      expect(log_output).to match(/BetterService/)
      expect(log_output).to match(/SubscribersTestService completed/)
      expect(log_output).to match(/\d+ms/)
      expect(log_output).to match(/user: 456/)
    end

    it "logs service.failed events with error level" do
      log_output = capture_log_output do
        service = SubscribersFailingService.new(user, params: {})
        service.call
      end

      expect(log_output).to match(/BetterService/)
      expect(log_output).to match(/SubscribersFailingService failed/)
      expect(log_output).to match(/execution_error/)
    end

    it "logs cache.hit events with debug level" do
      Rails.cache.clear

      # First call to populate cache
      service1 = SubscribersCachedService.new(user, params: { name: "test" })
      service1.call

      # Second call should hit cache
      log_output = capture_log_output do
        service2 = SubscribersCachedService.new(user, params: { name: "test" })
        service2.call
      end

      expect(log_output).to match(/BetterService::Cache/)
      expect(log_output).to match(/HIT/)
    end

    it "logs cache.miss events with debug level" do
      Rails.cache.clear

      log_output = capture_log_output do
        service = SubscribersCachedService.new(user, params: { name: "test" })
        service.call
      end

      expect(log_output).to match(/BetterService::Cache/)
      expect(log_output).to match(/MISS/)
    end
  end

  describe BetterService::Subscribers::StatsSubscriber, "Basic Stats" do
    it "tracks service executions" do
      service = SubscribersTestService.new(user, params: {})
      service.call

      # Get stats for first service (the full class name varies by test environment)
      service_name = BetterService::Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("SubscribersTestService") }
      stats = BetterService::Subscribers::StatsSubscriber.stats_for(service_name)

      expect(stats).not_to be_nil
      expect(stats[:executions]).to eq(1)
      expect(stats[:successes]).to eq(1)
      expect(stats[:failures]).to eq(0)
    end

    it "tracks multiple executions" do
      3.times do
        service = SubscribersTestService.new(user, params: {})
        service.call
      end

      # Get stats for first service (the full class name varies by test environment)
      service_name = BetterService::Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("SubscribersTestService") }
      stats = BetterService::Subscribers::StatsSubscriber.stats_for(service_name)

      expect(stats[:executions]).to eq(3)
      expect(stats[:successes]).to eq(3)
    end

    it "tracks failures" do
      service = SubscribersFailingService.new(user, params: {})
      service.call

      service_name = BetterService::Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("SubscribersFailingService") }
      stats = BetterService::Subscribers::StatsSubscriber.stats_for(service_name)

      expect(stats[:executions]).to eq(1)
      expect(stats[:successes]).to eq(0)
      expect(stats[:failures]).to eq(1)
    end

    it "tracks error types" do
      service = SubscribersFailingService.new(user, params: {})
      service.call

      service_name = BetterService::Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("SubscribersFailingService") }
      stats = BetterService::Subscribers::StatsSubscriber.stats_for(service_name)

      expect(stats[:errors]["execution_error"]).to eq(1)
    end

    it "tracks multiple error types" do
      # First error
      service = SubscribersFailingService.new(user, params: {})
      service.call

      # Second error of same type
      service = SubscribersFailingService.new(user, params: {})
      service.call

      service_name = BetterService::Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("SubscribersFailingService") }
      stats = BetterService::Subscribers::StatsSubscriber.stats_for(service_name)

      expect(stats[:errors]["execution_error"]).to eq(2)
    end
  end

  describe BetterService::Subscribers::StatsSubscriber, "Duration" do
    it "tracks total duration" do
      service = SubscribersTestService.new(user, params: {})
      service.call

      # Get stats for first service (the full class name varies by test environment)
      service_name = BetterService::Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("SubscribersTestService") }
      stats = BetterService::Subscribers::StatsSubscriber.stats_for(service_name)

      expect(stats[:total_duration]).to be > 0
    end

    it "calculates average duration" do
      # Execute twice
      2.times do
        service = SubscribersTestService.new(user, params: {})
        service.call
      end

      # Get stats for first service (the full class name varies by test environment)
      service_name = BetterService::Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("SubscribersTestService") }
      stats = BetterService::Subscribers::StatsSubscriber.stats_for(service_name)

      expect(stats[:executions]).to eq(2)
      expect(stats[:avg_duration]).to be > 0
      expect(stats[:avg_duration]).to eq((stats[:total_duration] / 2.0).round(2))
    end
  end

  describe BetterService::Subscribers::StatsSubscriber, "Cache Stats" do
    it "tracks cache hits" do
      Rails.cache.clear

      # First call - cache miss
      service1 = SubscribersCachedService.new(user, params: { name: "test" })
      service1.call

      # Second call - cache hit
      service2 = SubscribersCachedService.new(user, params: { name: "test" })
      service2.call

      service_name = BetterService::Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("SubscribersCachedService") }
      stats = BetterService::Subscribers::StatsSubscriber.stats_for(service_name)

      expect(stats[:cache_hits]).to eq(1)
    end

    it "tracks cache misses" do
      Rails.cache.clear

      service = SubscribersCachedService.new(user, params: { name: "test" })
      service.call

      service_name = BetterService::Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("SubscribersCachedService") }
      stats = BetterService::Subscribers::StatsSubscriber.stats_for(service_name)

      expect(stats[:cache_misses]).to eq(1)
    end
  end

  describe BetterService::Subscribers::StatsSubscriber, "Summary" do
    it "provides global summary" do
      # Execute multiple services
      service1 = SubscribersTestService.new(user, params: {})
      service1.call

      service2 = SubscribersTestService.new(user, params: {})
      service2.call

      service3 = SubscribersFailingService.new(user, params: {})
      service3.call

      summary = BetterService::Subscribers::StatsSubscriber.summary

      expect(summary[:total_services]).to eq(2) # TestService and FailingService
      expect(summary[:total_executions]).to eq(3)
      expect(summary[:total_successes]).to eq(2)
      expect(summary[:total_failures]).to eq(1)
      expect(summary[:success_rate]).to eq(66.67)
      expect(summary[:avg_duration]).to be > 0
    end

    it "summary calculates cache hit rate" do
      Rails.cache.clear

      # First call - miss
      service1 = SubscribersCachedService.new(user, params: { name: "test" })
      service1.call

      # Second call - hit
      service2 = SubscribersCachedService.new(user, params: { name: "test" })
      service2.call

      summary = BetterService::Subscribers::StatsSubscriber.summary

      expect(summary[:cache_hit_rate]).to eq(50.0)
    end
  end

  describe BetterService::Subscribers::StatsSubscriber, "Reset" do
    it "can be reset" do
      service = SubscribersTestService.new(user, params: {})
      service.call

      expect(BetterService::Subscribers::StatsSubscriber.stats.size).to be > 0

      BetterService::Subscribers::StatsSubscriber.reset!

      expect(BetterService::Subscribers::StatsSubscriber.stats.size).to eq(0)
    end
  end

  describe "Multiple Services" do
    it "tracks different services separately" do
      service1 = SubscribersTestService.new(user, params: {})
      service1.call

      service2 = SubscribersFailingService.new(user, params: {})
      service2.call

      test_service_name = BetterService::Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("SubscribersTestService") && !k.include?("Failing") }
      failing_service_name = BetterService::Subscribers::StatsSubscriber.stats.keys.find { |k| k.include?("SubscribersFailingService") }

      test_stats = BetterService::Subscribers::StatsSubscriber.stats_for(test_service_name)
      failing_stats = BetterService::Subscribers::StatsSubscriber.stats_for(failing_service_name)

      expect(test_stats[:executions]).to eq(1)
      expect(test_stats[:successes]).to eq(1)

      expect(failing_stats[:executions]).to eq(1)
      expect(failing_stats[:failures]).to eq(1)
    end
  end
end
