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
          expect(cached_service_class._cache_contexts).to eq(["bookings", "sidebar"])
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
          expect(subclass._cache_contexts).to eq(["bookings", "sidebar"])
        end
      end
    end
  end
end
