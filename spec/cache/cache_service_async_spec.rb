# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe BetterService::CacheService, "Async Operations" do
  include ActiveJob::TestHelper

  let(:user) { OpenStruct.new(id: 123) }
  let(:context_name) { "products" }

  before do
    Rails.cache.clear
    clear_enqueued_jobs
  end

  after do
    Rails.cache.clear
    clear_enqueued_jobs
  end

  describe "Async Invalidation - Job Enqueuing" do
    it "invalidate_for_context with async: true enqueues CacheInvalidationJob" do
      expect {
        described_class.invalidate_for_context(user, "products", async: true, cascade: false)
      }.to have_enqueued_job(BetterService::CacheService::CacheInvalidationJob)
    end

    it "invalidate_global with async: true enqueues CacheInvalidationJob" do
      expect {
        described_class.invalidate_global("sidebar", async: true, cascade: false)
      }.to have_enqueued_job(BetterService::CacheService::CacheInvalidationJob)
    end

    it "invalidate_for_user with async: true enqueues CacheInvalidationJob" do
      expect {
        described_class.invalidate_for_user(user, async: true)
      }.to have_enqueued_job(BetterService::CacheService::CacheInvalidationJob)
    end

    it "passes correct pattern to job for context" do
      expected_pattern = "*:user_123:*:products"

      expect {
        described_class.invalidate_for_context(user, "products", async: true)
      }.to have_enqueued_job(BetterService::CacheService::CacheInvalidationJob).with(expected_pattern)
    end

    it "passes correct pattern to job for global" do
      expected_pattern = "*:sidebar"

      expect {
        described_class.invalidate_global("sidebar", async: true)
      }.to have_enqueued_job(BetterService::CacheService::CacheInvalidationJob).with(expected_pattern)
    end

    it "passes correct pattern to job for user" do
      expected_pattern = "*:user_123:*"

      expect {
        described_class.invalidate_for_user(user, async: true)
      }.to have_enqueued_job(BetterService::CacheService::CacheInvalidationJob).with(expected_pattern)
    end
  end

  describe BetterService::CacheService::CacheInvalidationJob do
    it "performs cache deletion" do
      Rails.cache.write("products:user_123:abc:products", { data: "test" })
      Rails.cache.write("products:user_123:def:products", { data: "test2" })

      expect(Rails.cache.exist?("products:user_123:abc:products")).to be true

      pattern = "*:user_123:*:products"
      described_class.perform_now(pattern)

      expect(Rails.cache.exist?("products:user_123:abc:products")).to be false
      expect(Rails.cache.exist?("products:user_123:def:products")).to be false
    end

    it "handles empty pattern gracefully" do
      expect { described_class.perform_now("") }.not_to raise_error
    end

    it "handles nil pattern gracefully" do
      expect { described_class.perform_now(nil) }.not_to raise_error
    end

    it "uses default queue" do
      job = described_class.new("*:user_123:*")
      expect(job.queue_name.to_sym).to eq(:default)
    end

    it "can be serialized for retry" do
      pattern = "*:user_123:*:products"
      job = described_class.new(pattern)

      expect { job.serialize }.not_to raise_error
    end
  end

  describe "Async vs Sync Behavior" do
    it "async: true does not delete cache immediately" do
      Rails.cache.write("products:user_123:abc:products", { data: "test" })

      BetterService::CacheService.invalidate_for_context(user, "products", async: true)

      expect(Rails.cache.exist?("products:user_123:abc:products")).to be true

      perform_enqueued_jobs

      expect(Rails.cache.exist?("products:user_123:abc:products")).to be false
    end

    it "async: false deletes cache immediately" do
      Rails.cache.write("products:user_123:abc:products", { data: "test" })

      BetterService::CacheService.invalidate_for_context(user, "products", async: false)

      expect(Rails.cache.exist?("products:user_123:abc:products")).to be false
    end

    it "default behavior (no async param) deletes cache immediately" do
      Rails.cache.write("products:user_123:abc:products", { data: "test" })

      BetterService::CacheService.invalidate_for_context(user, "products")

      expect(Rails.cache.exist?("products:user_123:abc:products")).to be false
    end
  end

  describe "Multiple Async Invalidations" do
    it "multiple async invalidations enqueue multiple jobs" do
      expect {
        BetterService::CacheService.invalidate_for_context(user, "products", async: true, cascade: false)
        BetterService::CacheService.invalidate_global("sidebar", async: true, cascade: false)
        BetterService::CacheService.invalidate_for_user(user, async: true)
      }.to have_enqueued_job(BetterService::CacheService::CacheInvalidationJob).exactly(3).times
    end

    it "multiple async invalidations with same pattern enqueue separate jobs" do
      expect {
        BetterService::CacheService.invalidate_for_context(user, "products", async: true, cascade: false)
        BetterService::CacheService.invalidate_for_context(user, "products", async: true, cascade: false)
      }.to have_enqueued_job(BetterService::CacheService::CacheInvalidationJob).exactly(2).times
    end
  end

  describe "Async Logging" do
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

    it "logs queue message for async invalidation" do
      log_output = capture_log_output do
        BetterService::CacheService.invalidate_for_context(user, "products", async: true)
      end

      expect(log_output).to match(/BetterService::CacheService/)
      expect(log_output).to match(/Async invalidation queued/)
    end

    it "logs correct pattern for async invalidation" do
      log_output = capture_log_output do
        BetterService::CacheService.invalidate_global("sidebar", async: true)
      end

      expect(log_output).to match(/\*:sidebar/)
    end
  end

  describe "Error Handling in Async Jobs" do
    it "handles delete_matched errors by raising them" do
      pattern = "*:user_123:*:products"

      original_cache = Rails.cache
      error_cache = Object.new
      def error_cache.delete_matched(_)
        raise StandardError, "Cache error"
      end
      def error_cache.respond_to?(_method)
        true
      end

      Rails.cache = error_cache

      expect {
        BetterService::CacheService::CacheInvalidationJob.perform_now(pattern)
      }.to raise_error(StandardError, "Cache error")
    ensure
      Rails.cache = original_cache
    end
  end

  describe "Integration with perform_enqueued_jobs" do
    it "executes all async invalidations" do
      Rails.cache.write("products:user_123:abc:products", { data: "p1" })
      Rails.cache.write("sidebar:user_456:def:sidebar", { data: "s1" })
      Rails.cache.write("orders:user_789:ghi:orders", { data: "o1" })

      BetterService::CacheService.invalidate_for_context(user, "products", async: true)
      BetterService::CacheService.invalidate_global("sidebar", async: true)

      expect(Rails.cache.exist?("products:user_123:abc:products")).to be true
      expect(Rails.cache.exist?("sidebar:user_456:def:sidebar")).to be true

      perform_enqueued_jobs

      expect(Rails.cache.exist?("products:user_123:abc:products")).to be false
      expect(Rails.cache.exist?("sidebar:user_456:def:sidebar")).to be false
      expect(Rails.cache.exist?("orders:user_789:ghi:orders")).to be true
    end
  end
end
