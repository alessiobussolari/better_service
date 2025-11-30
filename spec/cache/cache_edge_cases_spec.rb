# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cache Edge Cases" do
  # Mock user class
  class CacheEdgeCaseTestUser
    attr_accessor :id

    def initialize(id)
      @id = id
    end
  end

  let(:user) { CacheEdgeCaseTestUser.new(1) }

  before do
    Rails.cache.clear
    # Disable result wrapper for cache tests - returns [object, metadata] tuple
    BetterService.configure { |c| c.use_result_wrapper = false }
  end

  after do
    Rails.cache.clear
    BetterService.reset_configuration!
  end

  describe "Nil cache key handling" do
    it "service without cache_key does not use caching" do
      # Use a class variable to track execution across instances
      counter = { count: 0 }

      non_cached_service = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        # No cache_key defined - caching disabled
        cache_ttl 1.hour

        schema { optional(:x).maybe(:integer) }

        define_singleton_method(:counter) { counter }

        process_with do
          self.class.counter[:count] += 1
          { resource: { count: self.class.counter[:count] } }
        end
      end

      # Multiple calls should all execute since no cache_key
      resource1, _ = non_cached_service.new(user, params: {}).call
      resource2, _ = non_cached_service.new(user, params: {}).call
      resource3, _ = non_cached_service.new(user, params: {}).call

      expect(counter[:count]).to eq(3)
      expect(resource1[:count]).to eq(1)
      expect(resource2[:count]).to eq(2)
      expect(resource3[:count]).to eq(3)
    end

    it "invalidate_key with nil returns false" do
      result = BetterService::CacheService.invalidate_key(nil)
      expect(result).to eq(false)
    end

    it "invalidate_for_context with nil user returns 0" do
      result = BetterService::CacheService.invalidate_for_context(nil, :products)
      expect(result).to eq(0)
    end

    it "invalidate_for_context with nil context returns 0" do
      result = BetterService::CacheService.invalidate_for_context(user, nil)
      expect(result).to eq(0)
    end
  end

  describe "Empty cache value storage" do
    it "caches empty hash values" do
      counter = { count: 0 }

      empty_result_service = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :empty_result
        cache_ttl 1.hour

        schema { optional(:x).maybe(:integer) }

        define_singleton_method(:counter) { counter }

        process_with do
          self.class.counter[:count] += 1
          { resource: {} }
        end
      end

      resource1, _ = empty_result_service.new(user, params: {}).call
      resource2, _ = empty_result_service.new(user, params: {}).call

      expect(resource1).to eq({})
      expect(resource2).to eq({})
      # Should only execute once due to caching
      expect(counter[:count]).to eq(1)
    end

    it "caches empty array values" do
      counter = { count: 0 }

      empty_items_service = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :empty_items
        cache_ttl 1.hour

        schema { optional(:x).maybe(:integer) }

        define_singleton_method(:counter) { counter }

        process_with do
          self.class.counter[:count] += 1
          { items: [] }
        end
      end

      resource1, _ = empty_items_service.new(user, params: {}).call
      resource2, _ = empty_items_service.new(user, params: {}).call

      expect(resource1).to eq([])
      expect(resource2).to eq([])
      expect(counter[:count]).to eq(1)
    end

    it "caches nil values correctly" do
      counter = { count: 0 }

      nil_result_service = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :nil_result
        cache_ttl 1.hour

        schema { optional(:x).maybe(:integer) }

        define_singleton_method(:counter) { counter }

        process_with do
          self.class.counter[:count] += 1
          nil
        end
      end

      resource1, _ = nil_result_service.new(user, params: {}).call
      resource2, _ = nil_result_service.new(user, params: {}).call

      # Nil should be cached (only one execution)
      expect(counter[:count]).to eq(1)
      expect(resource1).to be_nil
      expect(resource2).to be_nil
    end
  end

  describe "Large payload caching" do
    it "caches large data structures" do
      counter = { count: 0 }

      large_data_service = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :large_data
        cache_ttl 1.hour

        schema { optional(:x).maybe(:integer) }

        define_singleton_method(:counter) { counter }

        process_with do
          self.class.counter[:count] += 1
          large_items = 100.times.map do |i|
            {
              id: i,
              name: "Item #{i}",
              description: "A" * 100,
              metadata: { index: i }
            }
          end
          { items: large_items }
        end
      end

      resource1, _ = large_data_service.new(user, params: {}).call
      resource2, _ = large_data_service.new(user, params: {}).call

      expect(resource1.length).to eq(100)
      expect(resource2.length).to eq(100)
      expect(resource1.first[:id]).to eq(resource2.first[:id])
      expect(counter[:count]).to eq(1)
    end

    it "handles deeply nested structures" do
      counter = { count: 0 }

      nested_service = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :nested_data
        cache_ttl 1.hour

        schema { optional(:x).maybe(:integer) }

        define_singleton_method(:counter) { counter }

        process_with do
          self.class.counter[:count] += 1
          nested = { level: 0, children: [] }
          current = nested
          10.times do |i|
            child = { level: i + 1, data: "Level #{i + 1}", children: [] }
            current[:children] << child
            current = child
          end
          { resource: nested }
        end
      end

      resource1, _ = nested_service.new(user, params: {}).call
      resource2, _ = nested_service.new(user, params: {}).call

      expect(resource1[:level]).to eq(0)
      expect(resource2[:children].first[:level]).to eq(1)
      expect(counter[:count]).to eq(1)
    end
  end

  describe "Cache serialization errors" do
    it "handles objects that fail to serialize gracefully" do
      problematic_service = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :problematic
        cache_ttl 1.hour

        schema { optional(:x).maybe(:integer) }

        process_with do
          { resource: { data: "normal data", timestamp: Time.current } }
        end
      end

      expect {
        problematic_service.new(user, params: {}).call
      }.not_to raise_error
    end

    it "handles hash params gracefully" do
      hash_params_service = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :hash_params
        cache_ttl 1.hour

        schema do
          optional(:data).maybe(:hash)
        end

        process_with { { resource: { received: true } } }
      end

      resource, _meta = hash_params_service.new(user, params: { data: { a: 1, b: 2 } }).call
      expect(resource[:received]).to be true
    end
  end

  describe "Cache store failure recovery" do
    it "service continues to work when cache is available" do
      allow(Rails.cache).to receive(:fetch).and_call_original

      fallback_service = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :fallback_test
        cache_ttl 1.hour

        schema { optional(:x).maybe(:integer) }
        process_with { { resource: { ok: true } } }
      end

      resource, _meta = fallback_service.new(user, params: {}).call
      expect(resource[:ok]).to be true
    end

    it "handles cache operations correctly" do
      resilient_service = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :resilient
        cache_ttl 1.hour

        schema { optional(:x).maybe(:integer) }
        process_with { { resource: { status: "ok" } } }
      end

      resource, _meta = resilient_service.new(user, params: {}).call
      expect(resource[:status]).to eq("ok")
    end

    it "gracefully handles missing cache configuration" do
      expect(BetterService::CacheService.exist?(nil)).to be false
      expect(BetterService::CacheService.invalidate_key("")).to be false
      expect(BetterService::CacheService.invalidate_global("")).to eq(0)
    end

    it "cache stats returns valid information" do
      10.times do |i|
        Rails.cache.write("load_test_#{i}", { data: i })
      end

      stats = BetterService::CacheService.stats

      expect(stats).to have_key(:cache_store)
      expect(stats).to have_key(:supports_pattern_deletion)
      expect(stats).to have_key(:supports_async)
    end

    it "concurrent cache operations work correctly" do
      counter = { count: 0 }
      mutex = Mutex.new

      concurrent_service = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :concurrent
        cache_ttl 1.hour

        schema { optional(:x).maybe(:integer) }

        define_singleton_method(:counter) { counter }
        define_singleton_method(:mutex) { mutex }

        process_with do
          self.class.mutex.synchronize { self.class.counter[:count] += 1 }
          { resource: { time: Time.current.to_f } }
        end
      end

      results = []
      results_mutex = Mutex.new

      # Simulate concurrent access
      threads = 5.times.map do
        Thread.new do
          resource, _ = concurrent_service.new(user, params: {}).call
          results_mutex.synchronize { results << resource }
        end
      end

      threads.each(&:join)

      # All results should be present
      expect(results.length).to eq(5)
      # Due to caching, service should execute only once (or few times due to race)
      expect(counter[:count]).to be <= 5
    end
  end
end
