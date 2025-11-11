# frozen_string_literal: true

require "test_helper"
require "ostruct"

module BetterService
  class CacheServiceIntegrationTest < ActiveSupport::TestCase
    setup do
      @user = OpenStruct.new(id: 123)
      @user2 = OpenStruct.new(id: 456)
      Rails.cache.clear
    end

    teardown do
      Rails.cache.clear
    end

    # ========================================
    # Test Group: Direct Cache Key Invalidation
    # ========================================

    test "invalidation removes actual cache entries created with Rails.cache" do
      # Manually create cache entries matching BetterService pattern
      Rails.cache.write("service:user_123:hash1:products", { data: "test1" })
      Rails.cache.write("service:user_123:hash2:products", { data: "test2" })
      Rails.cache.write("service:user_456:hash3:products", { data: "test3" })

      # Verify they exist
      assert Rails.cache.exist?("service:user_123:hash1:products")
      assert Rails.cache.exist?("service:user_123:hash2:products")

      # Invalidate user 123's products
      CacheService.invalidate_for_context(@user, "products")

      # Verify user 123's are gone, user 456's remain
      assert_not Rails.cache.exist?("service:user_123:hash1:products")
      assert_not Rails.cache.exist?("service:user_123:hash2:products")
      assert Rails.cache.exist?("service:user_456:hash3:products")
    end

    test "global invalidation removes entries for all users" do
      Rails.cache.write("service:user_123:hash1:sidebar", { data: "u123" })
      Rails.cache.write("service:user_456:hash2:sidebar", { data: "u456" })
      Rails.cache.write("service:user_123:hash3:products", { data: "products" })

      CacheService.invalidate_global("sidebar")

      assert_not Rails.cache.exist?("service:user_123:hash1:sidebar")
      assert_not Rails.cache.exist?("service:user_456:hash2:sidebar")
      assert Rails.cache.exist?("service:user_123:hash3:products")
    end

    test "invalidate_for_user removes all user cache across contexts" do
      Rails.cache.write("service:user_123:hash1:products", { data: "p" })
      Rails.cache.write("service:user_123:hash2:sidebar", { data: "s" })
      Rails.cache.write("service:user_456:hash3:products", { data: "p2" })

      CacheService.invalidate_for_user(@user)

      assert_not Rails.cache.exist?("service:user_123:hash1:products")
      assert_not Rails.cache.exist?("service:user_123:hash2:sidebar")
      assert Rails.cache.exist?("service:user_456:hash3:products")
    end

    # ========================================
    # Test Group: Pattern Matching Accuracy
    # ========================================

    test "invalidation matches wildcard patterns correctly" do
      # Create entries with different patterns
      Rails.cache.write("prefix:user_123:middle:products", { data: "match1" })
      Rails.cache.write("otherprefix:user_123:middle:products", { data: "match2" })
      Rails.cache.write("prefix:user_456:middle:products", { data: "nomatch" })

      # Pattern *:user_123:*:products should match first two
      CacheService.invalidate_for_context(@user, "products")

      assert_not Rails.cache.exist?("prefix:user_123:middle:products")
      assert_not Rails.cache.exist?("otherprefix:user_123:middle:products")
      assert Rails.cache.exist?("prefix:user_456:middle:products")
    end

    test "context invalidation is case sensitive" do
      Rails.cache.write("service:user_123:hash:products", { data: "lowercase" })
      Rails.cache.write("service:user_123:hash:Products", { data: "uppercase" })

      CacheService.invalidate_for_context(@user, "products")

      assert_not Rails.cache.exist?("service:user_123:hash:products")
      assert Rails.cache.exist?("service:user_123:hash:Products")
    end

    # ========================================
    # Test Group: Clear All Functionality
    # ========================================

    test "clear_all removes all BetterService patterned cache" do
      Rails.cache.write("anything:user_123:hash:products", { data: "1" })
      Rails.cache.write("other:user_456:hash:sidebar", { data: "2" })
      Rails.cache.write("app:user_789:hash:dashboard", { data: "3" })
      Rails.cache.write("non_pattern_key", { data: "should_remain" })

      CacheService.clear_all

      assert_not Rails.cache.exist?("anything:user_123:hash:products")
      assert_not Rails.cache.exist?("other:user_456:hash:sidebar")
      assert_not Rails.cache.exist?("app:user_789:hash:dashboard")
      # Non-pattern key should remain
      assert Rails.cache.exist?("non_pattern_key")
    end

    # ========================================
    # Test Group: Multiple Users Same Context
    # ========================================

    test "user-specific invalidation does not affect other users in same context" do
      Rails.cache.write("service:user_123:hash1:products", { data: "u123" })
      Rails.cache.write("service:user_456:hash2:products", { data: "u456" })

      CacheService.invalidate_for_context(@user, "products")

      assert_not Rails.cache.exist?("service:user_123:hash1:products")
      assert Rails.cache.exist?("service:user_456:hash2:products")
    end

    test "global invalidation affects all users in context" do
      Rails.cache.write("service:user_123:hash1:products", { data: "u123" })
      Rails.cache.write("service:user_456:hash2:products", { data: "u456" })
      Rails.cache.write("service:user_789:hash3:products", { data: "u789" })

      CacheService.invalidate_global("products")

      assert_not Rails.cache.exist?("service:user_123:hash1:products")
      assert_not Rails.cache.exist?("service:user_456:hash2:products")
      assert_not Rails.cache.exist?("service:user_789:hash3:products")
    end

    # ========================================
    # Test Group: User Across Multiple Contexts
    # ========================================

    test "user has cache in multiple contexts, invalidate one leaves others" do
      Rails.cache.write("service:user_123:hash1:products", { data: "p" })
      Rails.cache.write("service:user_123:hash2:orders", { data: "o" })
      Rails.cache.write("service:user_123:hash3:sidebar", { data: "s" })

      CacheService.invalidate_for_context(@user, "products")

      assert_not Rails.cache.exist?("service:user_123:hash1:products")
      assert Rails.cache.exist?("service:user_123:hash2:orders")
      assert Rails.cache.exist?("service:user_123:hash3:sidebar")
    end

    # ========================================
    # Test Group: Special Characters in Context
    # ========================================

    test "context names with colons are handled correctly" do
      context_with_colon = "admin:settings"
      Rails.cache.write("service:user_123:hash:admin:settings", { data: "test" })

      CacheService.invalidate_for_context(@user, context_with_colon)

      assert_not Rails.cache.exist?("service:user_123:hash:admin:settings")
    end

    # ========================================
    # Test Group: Boundary Conditions
    # ========================================

    test "invalidation with no matching entries completes successfully" do
      # No cache entries exist
      assert_nothing_raised do
        count = CacheService.invalidate_for_context(@user, "nonexistent")
        assert_kind_of Integer, count
      end
    end

    test "multiple sequential invalidations work correctly" do
      Rails.cache.write("service:user_123:hash1:products", { data: "1" })
      Rails.cache.write("service:user_123:hash2:orders", { data: "2" })

      CacheService.invalidate_for_context(@user, "products")
      assert_not Rails.cache.exist?("service:user_123:hash1:products")
      assert Rails.cache.exist?("service:user_123:hash2:orders")

      CacheService.invalidate_for_context(@user, "orders")
      assert_not Rails.cache.exist?("service:user_123:hash2:orders")
    end
  end
end
