# frozen_string_literal: true

require "test_helper"

module BetterService
  module Concerns
    class CacheableTest < ActiveSupport::TestCase
      # Dummy user class for testing
      class DummyUser
        attr_accessor :id, :name

        def initialize(id: 1, name: "Test User")
          @id = id
          @name = name
        end
      end

      # Service with cache configured
      class CachedService < Services::Base
        cache_key "test_service"
        cache_ttl 30.minutes
        cache_contexts "bookings", "sidebar"

        search_with do
          { value: rand(1000) }
        end
      end

      # Service without cache
      class UncachedService < Services::Base
        search_with do
          { value: rand(1000) }
        end
      end

      # Mock CacheService for invalidation tests
      module CacheServiceMock
        @@calls = []

        def self.reset!
          @@calls = []
        end

        def self.calls
          @@calls
        end

        def self.invalidate_for_context(user, context)
          @@calls << { method: :invalidate_for_context, user: user, context: context }
        end

        def self.invalidate_global(context)
          @@calls << { method: :invalidate_global, context: context }
        end
      end

      def setup
        @user = DummyUser.new

        # Configure memory cache for testing
        @original_cache = Rails.cache
        Rails.cache = ActiveSupport::Cache::MemoryStore.new
        Rails.cache.clear

        CacheServiceMock.reset!

        # Replace CacheService with mock
        if defined?(BetterService::CacheService)
          @original_cache_service = BetterService.send(:remove_const, :CacheService)
        end
        BetterService.const_set(:CacheService, CacheServiceMock)
      end

      def teardown
        # Restore original cache
        Rails.cache = @original_cache

        # Restore original CacheService
        if defined?(BetterService::CacheService)
          BetterService.send(:remove_const, :CacheService)
        end
        if @original_cache_service
          BetterService.const_set(:CacheService, @original_cache_service)
        end
      end

      # ========================================
      # Test Group 1: Cache Configuration
      # ========================================

      test "cache_key DSL sets _cache_key" do
        assert_equal "test_service", CachedService._cache_key
      end

      test "cache_ttl DSL sets _cache_ttl" do
        assert_equal 30.minutes, CachedService._cache_ttl
      end

      test "cache_contexts DSL sets _cache_contexts" do
        assert_equal ["bookings", "sidebar"], CachedService._cache_contexts
      end

      test "cache attributes have correct defaults" do
        assert_nil Services::Base._cache_key
        assert_equal 15.minutes, Services::Base._cache_ttl
        assert_equal [], Services::Base._cache_contexts
      end

      test "cache_enabled? returns true when cache_key present" do
        service = CachedService.new(@user)

        assert service.send(:cache_enabled?)
      end

      test "cache_enabled? returns false when no cache_key" do
        service = Services::Base.new(@user)

        refute service.send(:cache_enabled?)
      end

      # ========================================
      # Test Group 2: Cache Key Building
      # ========================================

      test "build_cache_key includes user id" do
        service = CachedService.new(@user, params: { page: 1 })
        cache_key = service.send(:build_cache_key, @user)

        assert_includes cache_key, "test_service"
        assert_includes cache_key, "user_#{@user.id}"
      end

      test "build_cache_key uses global when user nil" do
        service = CachedService.new(@user)
        cache_key = service.send(:build_cache_key, nil)

        assert_includes cache_key, "global"
      end

      test "build_cache_key includes params signature" do
        service1 = CachedService.new(@user, params: { page: 1 })
        service2 = CachedService.new(@user, params: { page: 2 })

        key1 = service1.send(:build_cache_key, @user)
        key2 = service2.send(:build_cache_key, @user)

        refute_equal key1, key2
      end

      test "identical params generate identical cache key" do
        service1 = CachedService.new(@user, params: { page: 1, search: "test" })
        service2 = CachedService.new(@user, params: { page: 1, search: "test" })

        assert_equal service1.send(:build_cache_key, @user),
                     service2.send(:build_cache_key, @user)
      end

      test "cache key has expected format" do
        service = CachedService.new(@user, params: {})
        cache_key = service.send(:build_cache_key, @user)

        assert_match(/\Atest_service:user_\d+:[a-f0-9]{32}\z/, cache_key)
      end

      test "cache_params_signature generates MD5 hash" do
        service = CachedService.new(@user, params: { foo: "bar" })
        signature = service.send(:cache_params_signature)

        assert_equal 32, signature.length
        assert_match(/\A[a-f0-9]+\z/, signature)
      end

      # ========================================
      # Test Group 3: Cache Read/Write
      # ========================================

      test "call writes to cache on first execution" do
        Rails.cache.clear
        service = CachedService.new(@user)

        result = service.call

        assert result[:success]
        cache_key = service.send(:build_cache_key, @user)
        # Verify cache is used by reading it back
        cached_result = Rails.cache.read(cache_key)
        assert_not_nil cached_result
        assert_equal result, cached_result
      end

      test "call reads from cache on second execution" do
        Rails.cache.clear
        service1 = CachedService.new(@user, params: { page: 1 })

        # First call
        result1 = service1.call
        value1 = result1[:value]

        # Second call (same params, same user)
        service2 = CachedService.new(@user, params: { page: 1 })
        result2 = service2.call
        value2 = result2[:value]

        # Values should be identical (from cache)
        assert_equal value1, value2
      end

      test "cache respects TTL" do
        # This test verifies TTL is configured correctly
        # We can't easily test expiration without time travel
        service = CachedService.new(@user)

        result = service.call
        assert result[:success]

        # Verify the cache key exists
        cache_key = service.send(:build_cache_key, @user)
        cached_result = Rails.cache.read(cache_key)
        assert_not_nil cached_result
      end

      test "call skips cache when not enabled" do
        Rails.cache.clear
        service1 = UncachedService.new(@user)
        result1 = service1.call
        value1 = result1[:value]

        # Second call should have different value (not cached)
        service2 = UncachedService.new(@user)
        result2 = service2.call
        value2 = result2[:value]

        # Values should be different (random, not cached)
        refute_equal value1, value2
      end

      test "different users have separate cache entries" do
        user1 = DummyUser.new(id: 1)
        user2 = DummyUser.new(id: 2)

        service1 = CachedService.new(user1, params: { page: 1 })
        service2 = CachedService.new(user2, params: { page: 1 })

        service1.call
        service2.call

        key1 = service1.send(:build_cache_key, user1)
        key2 = service2.send(:build_cache_key, user2)

        refute_equal key1, key2
        # Both should have cached results
        cached1 = Rails.cache.read(key1)
        cached2 = Rails.cache.read(key2)
        assert_not_nil cached1
        assert_not_nil cached2
      end

      # ========================================
      # Test Group 4: Cache Invalidation
      # ========================================

      test "invalidate_cache_for calls CacheService with user" do
        service = CachedService.new(@user)

        service.send(:invalidate_cache_for, @user)

        assert_equal 2, CacheServiceMock.calls.length
        assert_equal :invalidate_for_context, CacheServiceMock.calls[0][:method]
        assert_equal @user, CacheServiceMock.calls[0][:user]
        assert_equal "bookings", CacheServiceMock.calls[0][:context]
        assert_equal "sidebar", CacheServiceMock.calls[1][:context]
      end

      test "invalidate_cache_for calls global invalidation when user nil" do
        service = CachedService.new(@user)

        service.send(:invalidate_cache_for, nil)

        assert_equal 2, CacheServiceMock.calls.length
        assert_equal :invalidate_global, CacheServiceMock.calls[0][:method]
        assert_equal "bookings", CacheServiceMock.calls[0][:context]
        assert_equal "sidebar", CacheServiceMock.calls[1][:context]
      end

      test "invalidate_cache_for does nothing when no contexts" do
        service = Class.new(Services::Base) do
          cache_key "test"
        end.new(@user)

        service.send(:invalidate_cache_for, @user)

        assert_empty CacheServiceMock.calls
      end

      test "global invalidation logs message" do
        service = CachedService.new(@user)

        # Just verify no error is raised
        assert_nothing_raised do
          service.send(:invalidate_cache_for, nil)
        end

        # Verify global invalidation was called
        assert_equal 2, CacheServiceMock.calls.count { |c| c[:method] == :invalidate_global }
      end

      test "invalidate_cache_for handles single context" do
        service = Class.new(Services::Base) do
          cache_contexts "bookings"
        end.new(@user)

        service.send(:invalidate_cache_for, @user)

        assert_equal 1, CacheServiceMock.calls.length
        assert_equal "bookings", CacheServiceMock.calls[0][:context]
      end

      test "cache_contexts inherited by subclasses" do
        subclass = Class.new(CachedService)

        assert_equal ["bookings", "sidebar"], subclass._cache_contexts
      end
    end
  end
end
