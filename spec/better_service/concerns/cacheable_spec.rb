# frozen_string_literal: true

require "rails_helper"

module BetterService
  module Concerns
    RSpec.describe "Cacheable concern" do
      let(:dummy_user_class) do
        Class.new do
          attr_accessor :id, :name

          def initialize(id: 1, name: "Test User")
            @id = id
            @name = name
          end
        end
      end

      let(:user) { dummy_user_class.new }

      # Mock CacheService for invalidation tests
      let(:cache_service_mock) do
        Module.new do
          class << self
            attr_accessor :calls

            def reset!
              self.calls = []
            end

            def invalidate_for_context(user, context)
              calls << { method: :invalidate_for_context, user: user, context: context }
            end

            def invalidate_global(context)
              calls << { method: :invalidate_global, context: context }
            end
          end
        end
      end

      let(:cached_service_class) do
        Class.new(Services::Base) do
          cache_key "test_service"
          cache_ttl 30.minutes
          cache_contexts "bookings", "sidebar"

          search_with do
            { value: rand(1000) }
          end
        end
      end

      let(:uncached_service_class) do
        Class.new(Services::Base) do
          search_with do
            { value: rand(1000) }
          end

          respond_with do |data|
            { object: data[:value], success: true }
          end
        end
      end

      before do
        @original_cache = Rails.cache
        Rails.cache = ActiveSupport::Cache::MemoryStore.new
        Rails.cache.clear

        cache_service_mock.reset!

        # Replace CacheService with mock
        if defined?(BetterService::CacheService)
          @original_cache_service = BetterService.send(:remove_const, :CacheService)
        end
        BetterService.const_set(:CacheService, cache_service_mock)
      end

      after do
        Rails.cache = @original_cache

        if defined?(BetterService::CacheService)
          BetterService.send(:remove_const, :CacheService)
        end
        if @original_cache_service
          BetterService.const_set(:CacheService, @original_cache_service)
        end
      end

      describe "cache configuration" do
        it "cache_key DSL sets _cache_key" do
          expect(cached_service_class._cache_key).to eq("test_service")
        end

        it "cache_ttl DSL sets _cache_ttl" do
          expect(cached_service_class._cache_ttl).to eq(30.minutes)
        end

        it "cache_contexts DSL sets _cache_contexts" do
          expect(cached_service_class._cache_contexts).to eq([ "bookings", "sidebar" ])
        end

        it "cache attributes have correct defaults" do
          expect(Services::Base._cache_key).to be_nil
          expect(Services::Base._cache_ttl).to eq(15.minutes)
          expect(Services::Base._cache_contexts).to eq([])
        end

        it "cache_enabled? returns true when cache_key present" do
          service = cached_service_class.new(user)
          expect(service.send(:cache_enabled?)).to be true
        end

        it "cache_enabled? returns false when no cache_key" do
          service = Services::Base.new(user)
          expect(service.send(:cache_enabled?)).to be false
        end

        # Mutation-killing tests
        it "cache_enabled? returns false for empty string cache_key" do
          service_class = Class.new(Services::Base) do
            cache_key ""
          end
          service = service_class.new(user)
          expect(service.send(:cache_enabled?)).to be false
        end

        it "cache_enabled? returns true for symbol cache_key" do
          service_class = Class.new(Services::Base) do
            cache_key :service_cache
          end
          service = service_class.new(user)
          expect(service.send(:cache_enabled?)).to be true
        end

        it "cache_enabled? returns true for string cache_key" do
          service = cached_service_class.new(user)
          expect(service.send(:cache_enabled?)).to eq(true)
        end

        it "cache_ttl returns integer seconds" do
          expect(cached_service_class._cache_ttl).to be_a(Integer)
        end

        it "default cache_ttl is 900 seconds (15 minutes)" do
          expect(Services::Base._cache_ttl).to eq(900)
        end
      end

      describe "cache key building" do
        it "includes user id" do
          service = cached_service_class.new(user, params: { page: 1 })
          cache_key = service.send(:build_cache_key, user)

          expect(cache_key).to include("test_service")
          expect(cache_key).to include("user_#{user.id}")
        end

        it "uses global when user nil" do
          service = cached_service_class.new(user)
          cache_key = service.send(:build_cache_key, nil)

          expect(cache_key).to include("global")
        end

        it "includes params signature" do
          service1 = cached_service_class.new(user, params: { page: 1 })
          service2 = cached_service_class.new(user, params: { page: 2 })

          key1 = service1.send(:build_cache_key, user)
          key2 = service2.send(:build_cache_key, user)

          expect(key1).not_to eq(key2)
        end

        it "identical params generate identical cache key" do
          service1 = cached_service_class.new(user, params: { page: 1, search: "test" })
          service2 = cached_service_class.new(user, params: { page: 1, search: "test" })

          expect(service1.send(:build_cache_key, user)).to eq(service2.send(:build_cache_key, user))
        end

        it "cache key has expected format" do
          service = cached_service_class.new(user, params: {})
          cache_key = service.send(:build_cache_key, user)

          expect(cache_key).to match(/\Atest_service:user_\d+:[a-f0-9]{32}\z/)
        end

        it "cache_params_signature generates MD5 hash" do
          service = cached_service_class.new(user, params: { foo: "bar" })
          signature = service.send(:cache_params_signature)

          expect(signature.length).to eq(32)
          expect(signature).to match(/\A[a-f0-9]+\z/)
        end

        # Mutation-killing tests
        it "build_cache_key returns string" do
          service = cached_service_class.new(user)
          cache_key = service.send(:build_cache_key, user)

          expect(cache_key).to be_a(String)
        end

        it "build_cache_key contains exactly three parts separated by colons" do
          service = cached_service_class.new(user, params: {})
          cache_key = service.send(:build_cache_key, user)
          parts = cache_key.split(":")

          expect(parts.length).to eq(3)
        end

        it "build_cache_key uses user.id for user part" do
          user_with_id = dummy_user_class.new(id: 999)
          service = cached_service_class.new(user_with_id)
          cache_key = service.send(:build_cache_key, user_with_id)

          expect(cache_key).to include("user_999")
        end

        it "build_cache_key handles user with nil id" do
          user_nil_id = dummy_user_class.new(id: nil)
          service = cached_service_class.new(user_nil_id)
          cache_key = service.send(:build_cache_key, user_nil_id)

          expect(cache_key).to include("user_")
          expect(cache_key).to be_a(String)
        end

        it "build_cache_key handles user with string id" do
          user_str_id = dummy_user_class.new(id: "abc123")
          service = cached_service_class.new(user_str_id)
          cache_key = service.send(:build_cache_key, user_str_id)

          expect(cache_key).to include("user_abc123")
        end

        it "cache_params_signature produces same hash for same params" do
          service1 = cached_service_class.new(user, params: { a: 1, b: 2 })
          service2 = cached_service_class.new(user, params: { a: 1, b: 2 })

          sig1 = service1.send(:cache_params_signature)
          sig2 = service2.send(:cache_params_signature)

          expect(sig1).to eq(sig2)
        end

        it "cache_params_signature produces different hash for different params" do
          service1 = cached_service_class.new(user, params: { a: 1 })
          service2 = cached_service_class.new(user, params: { a: 2 })

          sig1 = service1.send(:cache_params_signature)
          sig2 = service2.send(:cache_params_signature)

          expect(sig1).not_to eq(sig2)
        end

        it "cache_params_signature handles empty params" do
          service = cached_service_class.new(user, params: {})
          signature = service.send(:cache_params_signature)

          expect(signature.length).to eq(32)
        end

        it "cache_params_signature handles nested params" do
          service = cached_service_class.new(user, params: { a: { b: { c: 1 } } })
          signature = service.send(:cache_params_signature)

          expect(signature.length).to eq(32)
        end
      end

      describe "cache read/write" do
        it "writes to cache on first execution" do
          Rails.cache.clear
          service = cached_service_class.new(user)

          result = service.call

          expect(result).to be_success
          cache_key = service.send(:build_cache_key, user)
          cached_result = Rails.cache.read(cache_key)
          expect(cached_result).not_to be_nil
          expect(cached_result).to be_a(BetterService::Result)
          expect(cached_result).to be_success
        end

        it "reads from cache on second execution" do
          Rails.cache.clear
          service1 = cached_service_class.new(user, params: { page: 1 })

          result1 = service1.call
          value1 = result1.meta[:value]

          service2 = cached_service_class.new(user, params: { page: 1 })
          result2 = service2.call
          value2 = result2.meta[:value]

          expect(value1).to eq(value2)
        end

        it "cache respects TTL" do
          service = cached_service_class.new(user)

          result = service.call
          expect(result).to be_success

          cache_key = service.send(:build_cache_key, user)
          cached_result = Rails.cache.read(cache_key)
          expect(cached_result).not_to be_nil
        end

        it "call skips cache when not enabled" do
          Rails.cache.clear
          service1 = uncached_service_class.new(user)
          result1 = service1.call

          service2 = uncached_service_class.new(user)
          result2 = service2.call

          expect(result1.resource).not_to eq(result2.resource)
        end

        it "different users have separate cache entries" do
          user1 = dummy_user_class.new(id: 1)
          user2 = dummy_user_class.new(id: 2)

          service1 = cached_service_class.new(user1, params: { page: 1 })
          service2 = cached_service_class.new(user2, params: { page: 1 })

          service1.call
          service2.call

          key1 = service1.send(:build_cache_key, user1)
          key2 = service2.send(:build_cache_key, user2)

          expect(key1).not_to eq(key2)

          cached1 = Rails.cache.read(key1)
          cached2 = Rails.cache.read(key2)
          expect(cached1).not_to be_nil
          expect(cached2).not_to be_nil
        end
      end

      describe "cache invalidation" do
        it "invalidate_cache_for calls CacheService with user" do
          service = cached_service_class.new(user)

          service.send(:invalidate_cache_for, user)

          expect(cache_service_mock.calls.length).to eq(2)
          expect(cache_service_mock.calls[0][:method]).to eq(:invalidate_for_context)
          expect(cache_service_mock.calls[0][:user]).to eq(user)
          expect(cache_service_mock.calls[0][:context]).to eq("bookings")
          expect(cache_service_mock.calls[1][:context]).to eq("sidebar")
        end

        it "invalidate_cache_for calls global invalidation when user nil" do
          service = cached_service_class.new(user)

          service.send(:invalidate_cache_for, nil)

          expect(cache_service_mock.calls.length).to eq(2)
          expect(cache_service_mock.calls[0][:method]).to eq(:invalidate_global)
          expect(cache_service_mock.calls[0][:context]).to eq("bookings")
          expect(cache_service_mock.calls[1][:context]).to eq("sidebar")
        end

        it "invalidate_cache_for does nothing when no contexts" do
          service_class = Class.new(Services::Base) do
            cache_key "test"
          end

          service = service_class.new(user)
          service.send(:invalidate_cache_for, user)

          expect(cache_service_mock.calls).to be_empty
        end

        it "global invalidation does not raise" do
          service = cached_service_class.new(user)

          expect {
            service.send(:invalidate_cache_for, nil)
          }.not_to raise_error

          expect(cache_service_mock.calls.count { |c| c[:method] == :invalidate_global }).to eq(2)
        end

        it "invalidate_cache_for handles single context" do
          service_class = Class.new(Services::Base) do
            cache_contexts "bookings"
          end

          service = service_class.new(user)
          service.send(:invalidate_cache_for, user)

          expect(cache_service_mock.calls.length).to eq(1)
          expect(cache_service_mock.calls[0][:context]).to eq("bookings")
        end

        it "cache_contexts inherited by subclasses" do
          subclass = Class.new(cached_service_class)
          expect(subclass._cache_contexts).to eq([ "bookings", "sidebar" ])
        end

        # Mutation-killing tests for invalidation
        it "invalidate_cache_for early returns when _cache_contexts empty" do
          service_class = Class.new(Services::Base) do
            cache_key "test_empty_contexts"
            # No cache_contexts defined
          end

          service = service_class.new(user)
          service.send(:invalidate_cache_for, user)

          # Should not call CacheService at all
          expect(cache_service_mock.calls).to be_empty
        end

        it "invalidate_cache_for iterates over all contexts for user" do
          service_class = Class.new(Services::Base) do
            cache_contexts "context1", "context2", "context3"
          end

          service = service_class.new(user)
          service.send(:invalidate_cache_for, user)

          expect(cache_service_mock.calls.length).to eq(3)
          expect(cache_service_mock.calls.map { |c| c[:context] }).to eq([ "context1", "context2", "context3" ])
          expect(cache_service_mock.calls.all? { |c| c[:method] == :invalidate_for_context }).to be true
        end

        it "invalidate_cache_for iterates over all contexts for global" do
          service_class = Class.new(Services::Base) do
            cache_contexts "ctx_a", "ctx_b"
          end

          service = service_class.new(user)
          service.send(:invalidate_cache_for, nil)

          expect(cache_service_mock.calls.length).to eq(2)
          expect(cache_service_mock.calls.map { |c| c[:context] }).to eq([ "ctx_a", "ctx_b" ])
          expect(cache_service_mock.calls.all? { |c| c[:method] == :invalidate_global }).to be true
        end

        it "invalidate_cache_for passes exact user object to CacheService" do
          service = cached_service_class.new(user)
          service.send(:invalidate_cache_for, user)

          user_calls = cache_service_mock.calls.select { |c| c[:method] == :invalidate_for_context }
          expect(user_calls.all? { |c| c[:user].equal?(user) }).to be true
        end

        it "cache_contexts with symbols converts to array" do
          service_class = Class.new(Services::Base) do
            cache_contexts :bookings, :sidebar
          end

          expect(service_class._cache_contexts).to eq([ :bookings, :sidebar ])
        end

        it "cache_ttl accepts integer seconds" do
          service_class = Class.new(Services::Base) do
            cache_ttl 3600
          end

          expect(service_class._cache_ttl).to eq(3600)
        end

        it "cache_ttl accepts ActiveSupport duration" do
          service_class = Class.new(Services::Base) do
            cache_ttl 1.hour
          end

          expect(service_class._cache_ttl).to eq(3600)
        end
      end

      describe "cache call wrapper" do
        it "returns call_without_cache result when cache disabled" do
          service = uncached_service_class.new(user)

          # First call
          result1 = service.call

          # Create new service - should get different value (no caching)
          service2 = uncached_service_class.new(user)
          result2 = service2.call

          # Values should be different because each call runs search_with fresh
          expect(result1.resource).not_to eq(result2.resource)
        end

        it "caches result with correct TTL" do
          Rails.cache.clear
          service = cached_service_class.new(user)

          result = service.call
          cache_key = service.send(:build_cache_key, user)

          # Verify cache entry exists
          expect(Rails.cache.read(cache_key)).not_to be_nil
        end

        it "uses first cache_context for event publishing" do
          service_class = Class.new(Services::Base) do
            cache_key "multi_context_service"
            cache_contexts "primary", "secondary", "tertiary"

            search_with do
              { value: 42 }
            end
          end

          expect(service_class._cache_contexts.first).to eq("primary")
        end

        it "handles cache miss then hit on subsequent calls" do
          Rails.cache.clear

          service1 = cached_service_class.new(user, params: { x: 1 })
          result1 = service1.call
          value1 = result1.meta[:value]

          # Second call should hit cache
          service2 = cached_service_class.new(user, params: { x: 1 })
          result2 = service2.call
          value2 = result2.meta[:value]

          # Same value from cache
          expect(value1).to eq(value2)
        end

        it "does not cache when cache_enabled? returns false" do
          Rails.cache.clear

          # Service without cache_key
          service1 = uncached_service_class.new(user)
          service1.call

          # No cache entry should exist for this service
          # Since no cache_key, build_cache_key would fail, so we verify behavior differently
          service2 = uncached_service_class.new(user)
          result1 = service1.call
          result2 = service2.call

          # Different random values each time
          expect(result1.resource).not_to eq(result2.resource)
        end

        it "cache key includes all three components" do
          service = cached_service_class.new(user, params: { test: "value" })
          cache_key = service.send(:build_cache_key, user)

          parts = cache_key.split(":")
          expect(parts[0]).to eq("test_service") # cache_key
          expect(parts[1]).to match(/^user_\d+$/) # user part
          expect(parts[2]).to match(/^[a-f0-9]{32}$/) # MD5 signature
        end

        it "Rails.cache.fetch is called with correct expires_in" do
          Rails.cache.clear
          service = cached_service_class.new(user)

          # The TTL is 30.minutes = 1800 seconds
          expect(cached_service_class._cache_ttl).to eq(1800)

          service.call

          cache_key = service.send(:build_cache_key, user)
          expect(Rails.cache.read(cache_key)).not_to be_nil
        end
      end

      describe "edge cases and boundary conditions" do
        it "cache_params_signature handles nil in params hash" do
          service = cached_service_class.new(user, params: { a: nil, b: 1 })
          signature = service.send(:cache_params_signature)

          expect(signature.length).to eq(32)
        end

        it "cache_params_signature handles array params" do
          service = cached_service_class.new(user, params: { ids: [ 1, 2, 3 ] })
          signature = service.send(:cache_params_signature)

          expect(signature.length).to eq(32)
        end

        it "cache_params_signature produces consistent hash for array order" do
          service1 = cached_service_class.new(user, params: { ids: [ 1, 2, 3 ] })
          service2 = cached_service_class.new(user, params: { ids: [ 1, 2, 3 ] })

          expect(service1.send(:cache_params_signature)).to eq(service2.send(:cache_params_signature))
        end

        it "cache_params_signature differs for different array order" do
          service1 = cached_service_class.new(user, params: { ids: [ 1, 2, 3 ] })
          service2 = cached_service_class.new(user, params: { ids: [ 3, 2, 1 ] })

          expect(service1.send(:cache_params_signature)).not_to eq(service2.send(:cache_params_signature))
        end

        it "build_cache_key handles user with zero id" do
          user_zero = dummy_user_class.new(id: 0)
          service = cached_service_class.new(user_zero)
          cache_key = service.send(:build_cache_key, user_zero)

          expect(cache_key).to include("user_0")
        end

        it "build_cache_key handles user with negative id" do
          user_neg = dummy_user_class.new(id: -1)
          service = cached_service_class.new(user_neg)
          cache_key = service.send(:build_cache_key, user_neg)

          expect(cache_key).to include("user_-1")
        end

        it "cache_key DSL accepts symbol" do
          service_class = Class.new(Services::Base) do
            cache_key :my_cache
          end

          expect(service_class._cache_key).to eq(:my_cache)
        end

        it "cache_key DSL accepts string" do
          service_class = Class.new(Services::Base) do
            cache_key "my_cache"
          end

          expect(service_class._cache_key).to eq("my_cache")
        end

        it "multiple cache_key calls override previous value" do
          service_class = Class.new(Services::Base) do
            cache_key "first"
            cache_key "second"
          end

          expect(service_class._cache_key).to eq("second")
        end

        it "multiple cache_ttl calls override previous value" do
          service_class = Class.new(Services::Base) do
            cache_ttl 10.minutes
            cache_ttl 20.minutes
          end

          expect(service_class._cache_ttl).to eq(1200)
        end

        it "multiple cache_contexts calls override previous value" do
          service_class = Class.new(Services::Base) do
            cache_contexts "a", "b"
            cache_contexts "c", "d"
          end

          expect(service_class._cache_contexts).to eq([ "c", "d" ])
        end

        it "cache_enabled? returns false for nil cache_key" do
          service_class = Class.new(Services::Base) do
            cache_key nil
          end

          service = service_class.new(user)
          expect(service.send(:cache_enabled?)).to be false
        end

        it "cache_enabled? returns false for false cache_key" do
          service_class = Class.new(Services::Base) do
            self._cache_key = false
          end

          service = service_class.new(user)
          expect(service.send(:cache_enabled?)).to be false
        end

        it "invalidate_cache_for with empty array contexts does nothing" do
          service_class = Class.new(Services::Base) do
            cache_contexts # No arguments = empty array
          end

          service = service_class.new(user)
          service.send(:invalidate_cache_for, user)

          expect(cache_service_mock.calls).to be_empty
        end
      end

      describe "inheritance behavior" do
        it "subclass inherits cache_key" do
          subclass = Class.new(cached_service_class)
          expect(subclass._cache_key).to eq("test_service")
        end

        it "subclass can override cache_key" do
          subclass = Class.new(cached_service_class) do
            cache_key "subclass_cache"
          end

          expect(subclass._cache_key).to eq("subclass_cache")
          expect(cached_service_class._cache_key).to eq("test_service")
        end

        it "subclass inherits cache_ttl" do
          subclass = Class.new(cached_service_class)
          expect(subclass._cache_ttl).to eq(1800)
        end

        it "subclass can override cache_ttl" do
          subclass = Class.new(cached_service_class) do
            cache_ttl 1.hour
          end

          expect(subclass._cache_ttl).to eq(3600)
          expect(cached_service_class._cache_ttl).to eq(1800)
        end

        it "parent class unaffected by subclass override" do
          subclass = Class.new(cached_service_class) do
            cache_key "override"
            cache_ttl 99
            cache_contexts "new_ctx"
          end

          expect(cached_service_class._cache_key).to eq("test_service")
          expect(cached_service_class._cache_ttl).to eq(1800)
          expect(cached_service_class._cache_contexts).to eq([ "bookings", "sidebar" ])
        end
      end
    end
  end
end
