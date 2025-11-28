# frozen_string_literal: true

require "test_helper"
require "ostruct"

module BetterService
  class CacheServiceAsyncTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      # Clear cache and jobs before each test
      Rails.cache.clear
      clear_enqueued_jobs
      @user = OpenStruct.new(id: 123)
      @context = "products"
    end

    teardown do
      Rails.cache.clear
      clear_enqueued_jobs
    end

    # ========================================
    # Test Group: Async Invalidation - Job Enqueuing
    # ========================================

    test "invalidate_for_context with async: true enqueues CacheInvalidationJob" do
      assert_enqueued_with(job: CacheService::CacheInvalidationJob) do
        CacheService.invalidate_for_context(@user, "products", async: true)
      end
    end

    test "invalidate_global with async: true enqueues CacheInvalidationJob" do
      assert_enqueued_with(job: CacheService::CacheInvalidationJob) do
        CacheService.invalidate_global("sidebar", async: true)
      end
    end

    test "invalidate_for_user with async: true enqueues CacheInvalidationJob" do
      assert_enqueued_with(job: CacheService::CacheInvalidationJob) do
        CacheService.invalidate_for_user(@user, async: true)
      end
    end

    test "async invalidation passes correct pattern to job for context" do
      expected_pattern = "*:user_123:*:products"

      assert_enqueued_with(
        job: CacheService::CacheInvalidationJob,
        args: [ expected_pattern ]
      ) do
        CacheService.invalidate_for_context(@user, "products", async: true)
      end
    end

    test "async invalidation passes correct pattern to job for global" do
      expected_pattern = "*:sidebar"

      assert_enqueued_with(
        job: CacheService::CacheInvalidationJob,
        args: [ expected_pattern ]
      ) do
        CacheService.invalidate_global("sidebar", async: true)
      end
    end

    test "async invalidation passes correct pattern to job for user" do
      expected_pattern = "*:user_123:*"

      assert_enqueued_with(
        job: CacheService::CacheInvalidationJob,
        args: [ expected_pattern ]
      ) do
        CacheService.invalidate_for_user(@user, async: true)
      end
    end

    # ========================================
    # Test Group: CacheInvalidationJob Execution
    # ========================================

    test "CacheInvalidationJob performs cache deletion" do
      # Setup: Create cache entries
      Rails.cache.write("products:user_123:abc:products", { data: "test" })
      Rails.cache.write("products:user_123:def:products", { data: "test2" })

      # Verify setup
      assert Rails.cache.exist?("products:user_123:abc:products")

      # Execute job
      pattern = "*:user_123:*:products"
      CacheService::CacheInvalidationJob.perform_now(pattern)

      # Verify cache deleted
      assert_not Rails.cache.exist?("products:user_123:abc:products")
      assert_not Rails.cache.exist?("products:user_123:def:products")
    end

    test "CacheInvalidationJob handles empty pattern gracefully" do
      # Should not crash with empty pattern
      assert_nothing_raised do
        CacheService::CacheInvalidationJob.perform_now("")
      end
    end

    test "CacheInvalidationJob handles nil pattern gracefully" do
      # Should not crash with nil pattern
      assert_nothing_raised do
        CacheService::CacheInvalidationJob.perform_now(nil)
      end
    end

    # ========================================
    # Test Group: Async Job Queue Configuration
    # ========================================

    test "CacheInvalidationJob uses default queue" do
      job = CacheService::CacheInvalidationJob.new("*:user_123:*")
      assert_equal :default, job.queue_name.to_sym
    end

    # ========================================
    # Test Group: Async vs Sync Behavior
    # ========================================

    test "async: true does not delete cache immediately" do
      # Setup
      Rails.cache.write("products:user_123:abc:products", { data: "test" })

      # Execute async (just enqueues job)
      CacheService.invalidate_for_context(@user, "products", async: true)

      # Cache should still exist (job not performed yet)
      assert Rails.cache.exist?("products:user_123:abc:products")

      # Perform enqueued jobs
      perform_enqueued_jobs

      # Now cache should be deleted
      assert_not Rails.cache.exist?("products:user_123:abc:products")
    end

    test "async: false deletes cache immediately" do
      # Setup
      Rails.cache.write("products:user_123:abc:products", { data: "test" })

      # Execute sync
      CacheService.invalidate_for_context(@user, "products", async: false)

      # Cache should be deleted immediately
      assert_not Rails.cache.exist?("products:user_123:abc:products")
    end

    test "default behavior (no async param) deletes cache immediately" do
      # Setup
      Rails.cache.write("products:user_123:abc:products", { data: "test" })

      # Execute without async param (defaults to false)
      CacheService.invalidate_for_context(@user, "products")

      # Cache should be deleted immediately
      assert_not Rails.cache.exist?("products:user_123:abc:products")
    end

    # ========================================
    # Test Group: Multiple Async Invalidations
    # ========================================

    test "multiple async invalidations enqueue multiple jobs" do
      assert_enqueued_jobs 3, only: CacheService::CacheInvalidationJob do
        CacheService.invalidate_for_context(@user, "products", async: true, cascade: false)
        CacheService.invalidate_global("sidebar", async: true, cascade: false)
        CacheService.invalidate_for_user(@user, async: true)
      end
    end

    test "multiple async invalidations with same pattern enqueue separate jobs" do
      assert_enqueued_jobs 2, only: CacheService::CacheInvalidationJob do
        CacheService.invalidate_for_context(@user, "products", async: true, cascade: false)
        CacheService.invalidate_for_context(@user, "products", async: true, cascade: false)
      end
    end

    # ========================================
    # Test Group: Async Logging
    # ========================================

    test "async invalidation logs queue message" do
      log_output = capture_log_output do
        CacheService.invalidate_for_context(@user, "products", async: true)
      end

      assert_match(/BetterService::CacheService/, log_output)
      assert_match(/Async invalidation queued/, log_output)
    end

    test "async invalidation logs correct pattern" do
      log_output = capture_log_output do
        CacheService.invalidate_global("sidebar", async: true)
      end

      assert_match(/\*:sidebar/, log_output)
    end

    # ========================================
    # Test Group: Error Handling in Async Jobs
    # ========================================

    test "CacheInvalidationJob handles delete_matched errors by raising them" do
      # If delete_matched raises an error, the job should raise it
      # (letting ActiveJob handle retry logic)
      pattern = "*:user_123:*:products"

      # Create a mock cache store that raises error
      original_cache = Rails.cache
      error_cache = Object.new
      def error_cache.delete_matched(_)
        raise StandardError, "Cache error"
      end
      def error_cache.respond_to?(method)
        true
      end

      Rails.cache = error_cache

      # Should propagate the error
      assert_raises(StandardError, "Cache error") do
        CacheService::CacheInvalidationJob.perform_now(pattern)
      end
    ensure
      Rails.cache = original_cache
    end

    # ========================================
    # Test Group: Job Retry and Failure
    # ========================================

    test "CacheInvalidationJob can be retried on failure" do
      pattern = "*:user_123:*:products"

      # Create job
      job = CacheService::CacheInvalidationJob.new(pattern)

      # Verify job can be serialized for retry
      assert_nothing_raised do
        job.serialize
      end
    end

    # ========================================
    # Test Group: Integration with perform_enqueued_jobs
    # ========================================

    test "perform_enqueued_jobs executes all async invalidations" do
      # Setup: Create multiple cache entries
      Rails.cache.write("products:user_123:abc:products", { data: "p1" })
      Rails.cache.write("sidebar:user_456:def:sidebar", { data: "s1" })
      Rails.cache.write("orders:user_789:ghi:orders", { data: "o1" })

      # Enqueue multiple async invalidations
      CacheService.invalidate_for_context(@user, "products", async: true)
      CacheService.invalidate_global("sidebar", async: true)

      # Verify cache still exists
      assert Rails.cache.exist?("products:user_123:abc:products")
      assert Rails.cache.exist?("sidebar:user_456:def:sidebar")

      # Perform all jobs
      perform_enqueued_jobs

      # Verify cache deleted
      assert_not Rails.cache.exist?("products:user_123:abc:products")
      assert_not Rails.cache.exist?("sidebar:user_456:def:sidebar")
      # Unrelated cache should remain
      assert Rails.cache.exist?("orders:user_789:ghi:orders")
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
