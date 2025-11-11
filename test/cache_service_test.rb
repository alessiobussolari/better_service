# frozen_string_literal: true

require "test_helper"
require "ostruct"

module BetterService
  class CacheServiceTest < ActiveSupport::TestCase
    setup do
      # Clear cache before each test
      Rails.cache.clear
      @user = OpenStruct.new(id: 123)
      @context = "products"
    end

    teardown do
      Rails.cache.clear
    end

    # Test invalidate_for_context
    test "invalidate_for_context accepts user and context parameters" do
      result = CacheService.invalidate_for_context(@user, "products")
      # delete_matched returns Integer or Array depending on cache store
      assert result.is_a?(Integer) || result.is_a?(Array)
    end

    test "invalidate_for_context with integer user id" do
      result = CacheService.invalidate_for_context(999, "products")
      assert result.is_a?(Integer) || result.is_a?(Array)
    end

    test "invalidate_for_context returns 0 when user is nil" do
      count = CacheService.invalidate_for_context(nil, "products")
      assert_equal 0, count
    end

    test "invalidate_for_context returns 0 when context is nil" do
      count = CacheService.invalidate_for_context(@user, nil)
      assert_equal 0, count
    end

    # Test invalidate_global
    test "invalidate_global accepts context parameter" do
      result = CacheService.invalidate_global("sidebar")
      assert result.is_a?(Integer) || result.is_a?(Array)
    end

    test "invalidate_global returns 0 when context is nil" do
      count = CacheService.invalidate_global(nil)
      assert_equal 0, count
    end

    # Test invalidate_for_user
    test "invalidate_for_user accepts user parameter" do
      result = CacheService.invalidate_for_user(@user)
      assert result.is_a?(Integer) || result.is_a?(Array)
    end

    test "invalidate_for_user with integer user id" do
      result = CacheService.invalidate_for_user(789)
      assert result.is_a?(Integer) || result.is_a?(Array)
    end

    test "invalidate_for_user returns 0 when user is nil" do
      count = CacheService.invalidate_for_user(nil)
      assert_equal 0, count
    end

    # Test invalidate_key
    test "invalidate_key removes specific cache key" do
      # Setup
      key = "test_key_123"
      Rails.cache.write(key, { data: "test" })
      assert Rails.cache.exist?(key)

      # Execute
      result = CacheService.invalidate_key(key)

      # Verify
      assert_not Rails.cache.exist?(key)
      assert result
    end

    test "invalidate_key returns false when key is nil" do
      result = CacheService.invalidate_key(nil)
      assert_equal false, result
    end

    # Test clear_all
    test "clear_all returns result" do
      result = CacheService.clear_all
      assert result.is_a?(Integer) || result.is_a?(Array)
    end

    # Test fetch
    test "fetch returns cached value if exists" do
      key = "test_key"
      cached_value = { data: "cached" }
      Rails.cache.write(key, cached_value)

      result = CacheService.fetch(key) do
        { data: "fresh" }
      end

      assert_equal cached_value, result
    end

    test "fetch executes block and caches result if key missing" do
      key = "test_key_fetch_new"
      fresh_value = { data: "fresh" }

      result = CacheService.fetch(key) do
        fresh_value
      end

      assert_equal fresh_value, result
      assert_equal fresh_value, Rails.cache.read(key)
    end

    test "fetch respects expires_in option" do
      key = "test_key_expires"
      value = { data: "test" }

      result = CacheService.fetch(key, expires_in: 1.hour) do
        value
      end

      assert_equal value, result
      assert_equal value, Rails.cache.read(key)
    end

    test "fetch respects force option" do
      key = "test_key_force"
      Rails.cache.write(key, { data: "old" })

      result = CacheService.fetch(key, force: true) do
        { data: "new" }
      end

      assert_equal({ data: "new" }, result)
    end

    # Test exist?
    test "exist? returns true when key exists" do
      key = "test_key_exist"
      Rails.cache.write(key, { data: "test" })

      assert CacheService.exist?(key)
    end

    test "exist? returns false when key does not exist" do
      assert_not CacheService.exist?("nonexistent_key_12345")
    end

    # Test stats
    test "stats returns cache store information" do
      stats = CacheService.stats

      assert stats.key?(:cache_store)
      assert stats.key?(:supports_pattern_deletion)
      assert stats.key?(:supports_async)

      assert_not_nil stats[:cache_store]
      assert [ true, false ].include?(stats[:supports_pattern_deletion])
      assert [ true, false ].include?(stats[:supports_async])
    end

    # Test cache store compatibility
    test "supports_delete_matched? returns boolean" do
      result = CacheService.send(:supports_delete_matched?)
      assert_includes [ true, false ], result
    end

    # Test pattern building (private methods)
    test "build_user_context_pattern creates correct pattern" do
      pattern = CacheService.send(:build_user_context_pattern, @user, "products")
      assert_equal "*:user_123:*:products", pattern
    end

    test "build_user_context_pattern handles integer user id" do
      pattern = CacheService.send(:build_user_context_pattern, 456, "sidebar")
      assert_equal "*:user_456:*:sidebar", pattern
    end

    test "build_global_context_pattern creates correct pattern" do
      pattern = CacheService.send(:build_global_context_pattern, "dashboard")
      assert_equal "*:dashboard", pattern
    end

    test "build_user_pattern creates correct pattern" do
      pattern = CacheService.send(:build_user_pattern, @user)
      assert_equal "*:user_123:*", pattern
    end

    test "build_user_pattern handles integer user id" do
      pattern = CacheService.send(:build_user_pattern, 789)
      assert_equal "*:user_789:*", pattern
    end

    # ========================================
    # Test Group: Actual Cache Deletion Verification
    # ========================================

    test "invalidate_for_context actually deletes matching cache entries" do
      # Setup: Create cache entries with the expected pattern
      Rails.cache.write("products_index:user_123:abc123:products", { data: "product 1" })
      Rails.cache.write("products_index:user_123:def456:products", { data: "product 2" })
      Rails.cache.write("products_index:user_456:ghi789:products", { data: "other user" })
      Rails.cache.write("sidebar:user_123:jkl012:sidebar", { data: "sidebar" })

      # Verify setup
      assert Rails.cache.exist?("products_index:user_123:abc123:products")
      assert Rails.cache.exist?("products_index:user_123:def456:products")

      # Execute
      CacheService.invalidate_for_context(@user, "products")

      # Verify: Only user 123's products cache should be deleted
      assert_not Rails.cache.exist?("products_index:user_123:abc123:products")
      assert_not Rails.cache.exist?("products_index:user_123:def456:products")
      # Other entries should remain
      assert Rails.cache.exist?("products_index:user_456:ghi789:products")
      assert Rails.cache.exist?("sidebar:user_123:jkl012:sidebar")
    end

    test "invalidate_global actually deletes all cache entries for context" do
      # Setup: Create cache entries for multiple users
      Rails.cache.write("sidebar:user_123:abc:sidebar", { data: "user 123 sidebar" })
      Rails.cache.write("sidebar:user_456:def:sidebar", { data: "user 456 sidebar" })
      Rails.cache.write("sidebar:user_789:ghi:sidebar", { data: "user 789 sidebar" })
      Rails.cache.write("products_index:user_123:xyz:products", { data: "products" })

      # Verify setup
      assert Rails.cache.exist?("sidebar:user_123:abc:sidebar")
      assert Rails.cache.exist?("sidebar:user_456:def:sidebar")
      assert Rails.cache.exist?("sidebar:user_789:ghi:sidebar")

      # Execute
      CacheService.invalidate_global("sidebar")

      # Verify: All sidebar cache deleted, products remain
      assert_not Rails.cache.exist?("sidebar:user_123:abc:sidebar")
      assert_not Rails.cache.exist?("sidebar:user_456:def:sidebar")
      assert_not Rails.cache.exist?("sidebar:user_789:ghi:sidebar")
      assert Rails.cache.exist?("products_index:user_123:xyz:products")
    end

    test "invalidate_for_user actually deletes all cache for specific user" do
      # Setup: Create cache entries for user across multiple contexts
      Rails.cache.write("products_index:user_123:abc:products", { data: "products" })
      Rails.cache.write("sidebar:user_123:def:sidebar", { data: "sidebar" })
      Rails.cache.write("dashboard:user_123:ghi:dashboard", { data: "dashboard" })
      Rails.cache.write("products_index:user_456:abc:products", { data: "other user" })

      # Verify setup
      assert Rails.cache.exist?("products_index:user_123:abc:products")
      assert Rails.cache.exist?("sidebar:user_123:def:sidebar")
      assert Rails.cache.exist?("dashboard:user_123:ghi:dashboard")

      # Execute
      CacheService.invalidate_for_user(@user)

      # Verify: All user 123 cache deleted, user 456 remains
      assert_not Rails.cache.exist?("products_index:user_123:abc:products")
      assert_not Rails.cache.exist?("sidebar:user_123:def:sidebar")
      assert_not Rails.cache.exist?("dashboard:user_123:ghi:dashboard")
      assert Rails.cache.exist?("products_index:user_456:abc:products")
    end

    test "invalidation does not delete non-matching entries" do
      # Setup: Create diverse cache entries
      Rails.cache.write("products_index:user_123:abc:products", { data: "target" })
      Rails.cache.write("products_index:user_456:def:products", { data: "different user" })
      Rails.cache.write("sidebar:user_123:ghi:sidebar", { data: "different context" })
      Rails.cache.write("unrelated_key", { data: "unrelated" })

      # Execute: Invalidate only user 123's products
      CacheService.invalidate_for_context(@user, "products")

      # Verify: Only target entry deleted
      assert_not Rails.cache.exist?("products_index:user_123:abc:products")
      assert Rails.cache.exist?("products_index:user_456:def:products")
      assert Rails.cache.exist?("sidebar:user_123:ghi:sidebar")
      assert Rails.cache.exist?("unrelated_key")
    end

    test "clear_all actually removes all BetterService cache" do
      # Setup: Create various BetterService cache entries
      Rails.cache.write("products_index:user_123:abc:products", { data: "products" })
      Rails.cache.write("sidebar:user_456:def:sidebar", { data: "sidebar" })
      Rails.cache.write("dashboard:user_789:ghi:dashboard", { data: "dashboard" })
      Rails.cache.write("unrelated_key_without_pattern", { data: "should remain" })

      # Verify setup
      assert Rails.cache.exist?("products_index:user_123:abc:products")
      assert Rails.cache.exist?("sidebar:user_456:def:sidebar")

      # Execute
      CacheService.clear_all

      # Verify: All BetterService cache deleted
      assert_not Rails.cache.exist?("products_index:user_123:abc:products")
      assert_not Rails.cache.exist?("sidebar:user_456:def:sidebar")
      assert_not Rails.cache.exist?("dashboard:user_789:ghi:dashboard")
      # Note: Pattern *:user_*:* should not match keys without this pattern
    end

    # ========================================
    # Test Group: Edge Cases
    # ========================================

    test "invalidate_for_context with empty string context" do
      count = CacheService.invalidate_for_context(@user, "")
      assert_equal 0, count
    end

    test "invalidate_for_context with whitespace context" do
      # Whitespace context should still work (it's technically valid)
      result = CacheService.invalidate_for_context(@user, "   ")
      # Should not crash, but may return 0 or empty result
      assert result.is_a?(Integer) || result.is_a?(Array)
    end

    test "invalidate_global with empty string context" do
      count = CacheService.invalidate_global("")
      assert_equal 0, count
    end

    test "invalidate_for_user with user object having nil id" do
      user_with_nil_id = OpenStruct.new(id: nil)
      # Should handle gracefully by extracting nil
      pattern = CacheService.send(:build_user_pattern, user_with_nil_id)
      assert_equal "*:user_:*", pattern
    end

    test "invalidate_key with non-existent key returns true" do
      result = CacheService.invalidate_key("non_existent_key_xyz")
      # invalidate_key always returns true for valid keys (whether they exist or not)
      assert_equal true, result
    end

    test "invalidate_key with empty string" do
      result = CacheService.invalidate_key("")
      # Empty string is falsy in the guard clause
      assert_equal false, result
    end

    test "build_user_context_pattern with string user id" do
      user_with_string_id = OpenStruct.new(id: "abc123")
      pattern = CacheService.send(:build_user_context_pattern, user_with_string_id, "products")
      assert_equal "*:user_abc123:*:products", pattern
    end

    test "build_user_pattern with zero id" do
      user_with_zero_id = OpenStruct.new(id: 0)
      pattern = CacheService.send(:build_user_pattern, user_with_zero_id)
      assert_equal "*:user_0:*", pattern
    end

    test "context names with special characters" do
      # Context with colon (common separator)
      pattern = CacheService.send(:build_global_context_pattern, "admin:settings")
      assert_equal "*:admin:settings", pattern

      # Context with wildcard (could cause issues with pattern matching)
      pattern_with_wildcard = CacheService.send(:build_global_context_pattern, "products*")
      assert_equal "*:products*", pattern_with_wildcard
    end

    # ========================================
    # Test Group: Advanced fetch Scenarios
    # ========================================

    test "fetch with nil value returned by block" do
      key = "test_key_nil_value"

      result = CacheService.fetch(key) do
        nil
      end

      # Verify nil is cached (not treated as cache miss)
      assert_nil result
      # On second fetch, should return cached nil without executing block
      execution_count = 0
      result2 = CacheService.fetch(key) do
        execution_count += 1
        "should not execute"
      end

      assert_nil result2
      assert_equal 0, execution_count, "Block should not execute when nil is cached"
    end

    test "fetch with exception in block" do
      key = "test_key_exception"

      assert_raises(StandardError) do
        CacheService.fetch(key) do
          raise StandardError, "Block error"
        end
      end

      # Verify nothing was cached
      assert_not Rails.cache.exist?(key)
    end

    test "fetch with multiple options" do
      key = "test_key_multi_options"
      value = { data: "test" }

      result = CacheService.fetch(key, expires_in: 1.hour, race_condition_ttl: 10) do
        value
      end

      assert_equal value, result
      assert Rails.cache.exist?(key)
    end

    # ========================================
    # Test Group: exist? Advanced Tests
    # ========================================

    test "exist? returns false after invalidation" do
      key = "test_key_invalidation"
      Rails.cache.write(key, { data: "test" })
      assert CacheService.exist?(key)

      CacheService.invalidate_key(key)
      assert_not CacheService.exist?(key)
    end

    test "exist? with nil key returns false" do
      assert_not CacheService.exist?(nil)
    end

    test "exist? with key containing special characters" do
      key = "test:key:with:colons"
      Rails.cache.write(key, { data: "test" })

      assert CacheService.exist?(key)
    end

    # ========================================
    # Test Group: Logging Tests
    # ========================================

    test "invalidate_for_context logs invalidation count" do
      # Create cache entries to invalidate
      Rails.cache.write("products:user_123:abc:products", { data: "test" })

      # Capture log output
      log_output = capture_log_output do
        CacheService.invalidate_for_context(@user, "products")
      end

      # Verify log contains expected message
      assert_match(/BetterService::CacheService/, log_output)
      assert_match(/Invalidated/, log_output)
    end

    test "invalidate_global logs invalidation" do
      Rails.cache.write("sidebar:user_123:abc:sidebar", { data: "test" })

      log_output = capture_log_output do
        CacheService.invalidate_global("sidebar")
      end

      assert_match(/BetterService::CacheService/, log_output)
      assert_match(/Invalidated/, log_output)
    end

    test "logging handles nil Rails.logger gracefully" do
      original_logger = Rails.logger
      Rails.logger = nil

      # Should not raise error
      assert_nothing_raised do
        CacheService.invalidate_for_context(@user, "products")
      end
    ensure
      Rails.logger = original_logger
    end

    # ========================================
    # Test Group: Cache Store Compatibility
    # ========================================

    test "supports_delete_matched? returns true for MemoryStore" do
      # Test environment uses MemoryStore which supports delete_matched
      assert CacheService.send(:supports_delete_matched?)
    end

    test "stats reflects actual cache store class" do
      stats = CacheService.stats
      assert_equal Rails.cache.class.name, stats[:cache_store]
    end

    test "stats shows pattern deletion support correctly" do
      stats = CacheService.stats
      expected_support = Rails.cache.respond_to?(:delete_matched)
      assert_equal expected_support, stats[:supports_pattern_deletion]
    end

    test "stats shows async support as boolean" do
      stats = CacheService.stats
      assert_includes [ true, false ], stats[:supports_async]
    end

    # ========================================
    # Test Group: Multiple Users and Contexts
    # ========================================

    test "invalidation works correctly with multiple users sharing same context" do
      # User 123
      Rails.cache.write("products:user_123:abc:products", { data: "user 123 products" })
      # User 456
      Rails.cache.write("products:user_456:def:products", { data: "user 456 products" })

      # Invalidate only user 123
      CacheService.invalidate_for_context(@user, "products")

      assert_not Rails.cache.exist?("products:user_123:abc:products")
      assert Rails.cache.exist?("products:user_456:def:products")
    end

    test "invalidation works with user across multiple contexts" do
      Rails.cache.write("products:user_123:abc:products", { data: "products" })
      Rails.cache.write("orders:user_123:def:orders", { data: "orders" })
      Rails.cache.write("sidebar:user_123:ghi:sidebar", { data: "sidebar" })

      # Invalidate only products context
      CacheService.invalidate_for_context(@user, "products")

      assert_not Rails.cache.exist?("products:user_123:abc:products")
      assert Rails.cache.exist?("orders:user_123:def:orders")
      assert Rails.cache.exist?("sidebar:user_123:ghi:sidebar")
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
