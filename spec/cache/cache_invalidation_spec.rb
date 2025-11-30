# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cache Invalidation Scenarios" do
  # Mock user class for testing
  class CacheInvalidationTestUser
    attr_accessor :id, :email

    def initialize(id, email: "test@example.com")
      @id = id
      @email = email
    end
  end

  let(:user) { CacheInvalidationTestUser.new(1) }
  let(:other_user) { CacheInvalidationTestUser.new(2) }

  before do
    Rails.cache.clear
    # Disable result wrapper for cache tests - returns [object, metadata] tuple
    BetterService.configure { |c| c.use_result_wrapper = false }
  end

  after do
    Rails.cache.clear
    BetterService.reset_configuration!
  end

  describe "TTL expiration behavior" do
    it "cache expires after TTL" do
      counter = { count: 0 }

      service_class = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :short_ttl_test
        cache_ttl 1 # 1 second

        schema do
          optional(:value).maybe(:integer)
        end

        define_singleton_method(:counter) { counter }

        process_with do |_data|
          self.class.counter[:count] += 1
          { resource: { timestamp: Time.current.to_f, count: self.class.counter[:count] } }
        end
      end

      # First call - caches the result
      resource1, _meta1 = service_class.new(user, params: { value: 1 }).call
      timestamp1 = resource1[:timestamp]

      # Immediate second call - should return cached value
      resource2, _meta2 = service_class.new(user, params: { value: 1 }).call
      timestamp2 = resource2[:timestamp]

      expect(timestamp1).to eq(timestamp2)
      expect(counter[:count]).to eq(1) # Only executed once

      # Wait for TTL to expire
      sleep(1.5)

      # Third call - cache should be expired, new value
      resource3, _meta3 = service_class.new(user, params: { value: 1 }).call
      timestamp3 = resource3[:timestamp]

      expect(timestamp3).not_to eq(timestamp1)
      expect(counter[:count]).to eq(2) # Executed again after expiry
    end

    it "different TTL values are respected" do
      short_counter = { count: 0 }
      long_counter = { count: 0 }

      short_ttl_class = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable
        cache_key :short_ttl
        cache_ttl 1 # 1 second

        schema { optional(:x).maybe(:integer) }

        define_singleton_method(:counter) { short_counter }

        process_with do
          self.class.counter[:count] += 1
          { resource: { t: Time.current.to_f } }
        end
      end

      long_ttl_class = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable
        cache_key :long_ttl
        cache_ttl 1.hour

        schema { optional(:x).maybe(:integer) }

        define_singleton_method(:counter) { long_counter }

        process_with do
          self.class.counter[:count] += 1
          { resource: { t: Time.current.to_f } }
        end
      end

      short_resource1, _ = short_ttl_class.new(user, params: {}).call
      long_resource1, _ = long_ttl_class.new(user, params: {}).call

      expect(short_counter[:count]).to eq(1)
      expect(long_counter[:count]).to eq(1)

      sleep(1.5)

      short_resource2, _ = short_ttl_class.new(user, params: {}).call
      long_resource2, _ = long_ttl_class.new(user, params: {}).call

      # Short TTL should have expired (executed again)
      expect(short_counter[:count]).to eq(2)
      expect(short_resource2[:t]).not_to eq(short_resource1[:t])

      # Long TTL should still be cached (not executed again)
      expect(long_counter[:count]).to eq(1)
      expect(long_resource2[:t]).to eq(long_resource1[:t])
    end
  end

  describe "Manual invalidation timing" do
    it "invalidation clears cache immediately" do
      # Write directly to cache with known pattern
      cache_key = "test:user_1:abc:products"
      Rails.cache.write(cache_key, { data: "cached" })

      expect(Rails.cache.exist?(cache_key)).to be true

      # Manually invalidate
      BetterService::CacheService.invalidate_for_context(user, :products)

      # Cache should be cleared
      expect(Rails.cache.exist?(cache_key)).to be false
    end

    it "invalidation affects specific user only" do
      # Populate cache for both users
      user1_key = "test:user_1:abc:products"
      user2_key = "test:user_2:def:products"

      Rails.cache.write(user1_key, { data: "user 1" })
      Rails.cache.write(user2_key, { data: "user 2" })

      expect(Rails.cache.exist?(user1_key)).to be true
      expect(Rails.cache.exist?(user2_key)).to be true

      # Invalidate only user 1
      BetterService::CacheService.invalidate_for_context(user, :products)

      expect(Rails.cache.exist?(user1_key)).to be false
      expect(Rails.cache.exist?(user2_key)).to be true
    end
  end

  describe "Context-based invalidation propagation" do
    it "invalidates specific context only" do
      # Set up cache entries for multiple contexts
      Rails.cache.write("test:user_1:abc:products", { data: "product cache" })
      Rails.cache.write("test:user_1:def:orders", { data: "order cache" })

      expect(Rails.cache.exist?("test:user_1:abc:products")).to be true
      expect(Rails.cache.exist?("test:user_1:def:orders")).to be true

      # Invalidate products context
      BetterService::CacheService.invalidate_for_context(user, :products)

      # Only products context should be cleared
      expect(Rails.cache.exist?("test:user_1:abc:products")).to be false
      expect(Rails.cache.exist?("test:user_1:def:orders")).to be true
    end

    it "global invalidation clears all users for context" do
      # Set up cache for multiple users
      Rails.cache.write("list:user_1:abc:products", { data: "user 1" })
      Rails.cache.write("list:user_2:def:products", { data: "user 2" })
      Rails.cache.write("list:user_3:ghi:products", { data: "user 3" })

      BetterService::CacheService.invalidate_global(:products)

      expect(Rails.cache.exist?("list:user_1:abc:products")).to be false
      expect(Rails.cache.exist?("list:user_2:def:products")).to be false
      expect(Rails.cache.exist?("list:user_3:ghi:products")).to be false
    end
  end

  describe "Cache miss on first call" do
    it "executes service logic on cache miss" do
      counter = { count: 0 }

      counting_service = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :counting_service
        cache_ttl 1.hour

        schema { optional(:x).maybe(:integer) }

        define_singleton_method(:counter) { counter }

        process_with do
          self.class.counter[:count] += 1
          { resource: { count: self.class.counter[:count] } }
        end
      end

      # First call - cache miss
      resource, _meta = counting_service.new(user, params: {}).call

      expect(resource[:count]).to eq(1)
      expect(counter[:count]).to eq(1)
    end

    it "returns fresh data on first call" do
      service_class = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :fresh_data
        cache_ttl 1.hour

        schema { required(:id).filled(:integer) }

        process_with do
          { resource: { id: params[:id], name: "Product #{params[:id]}", fetched_at: Time.current.to_f } }
        end
      end

      resource, _meta = service_class.new(user, params: { id: 123 }).call

      expect(resource[:id]).to eq(123)
      expect(resource[:name]).to eq("Product 123")
      expect(resource[:fetched_at]).to be_present
    end
  end

  describe "Cache hit on second call" do
    it "returns cached data without re-executing service" do
      counter = { count: 0 }

      counting_service = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :cache_hit_test
        cache_ttl 1.hour

        schema { optional(:x).maybe(:integer) }

        define_singleton_method(:counter) { counter }

        process_with do
          self.class.counter[:count] += 1
          { resource: { count: self.class.counter[:count], timestamp: Time.current.to_f } }
        end
      end

      # First call
      resource1, _meta1 = counting_service.new(user, params: {}).call
      timestamp1 = resource1[:timestamp]

      # Second call - should hit cache
      resource2, _meta2 = counting_service.new(user, params: {}).call
      timestamp2 = resource2[:timestamp]

      # Service should only execute once
      expect(counter[:count]).to eq(1)
      # Both results should have same timestamp
      expect(timestamp1).to eq(timestamp2)
    end

    it "cache key includes params signature" do
      counter = { count: 0 }

      service_class = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable

        cache_key :params_signature
        cache_ttl 1.hour

        schema { required(:id).filled(:integer) }

        define_singleton_method(:counter) { counter }

        process_with do
          self.class.counter[:count] += 1
          { resource: { id: params[:id] } }
        end
      end

      # Different params = different cache keys = separate executions
      resource1, _ = service_class.new(user, params: { id: 1 }).call
      resource2, _ = service_class.new(user, params: { id: 2 }).call

      expect(resource1[:id]).to eq(1)
      expect(resource2[:id]).to eq(2)
      expect(counter[:count]).to eq(2) # Both executed separately
    end
  end

  describe "Invalidation after CUD operations" do
    it "auto-invalidates cache when triggered" do
      # Set up cache entry
      cache_key = "products:user_1:xyz:products"
      Rails.cache.write(cache_key, { data: "cached products" })
      expect(Rails.cache.exist?(cache_key)).to be true

      # Simulate what a create service would do
      BetterService::CacheService.invalidate_for_context(user, :products)

      # Cache should be invalidated
      expect(Rails.cache.exist?(cache_key)).to be false
    end
  end

  describe "Selective cache invalidation" do
    it "invalidates only specified context" do
      # Set up multiple contexts
      Rails.cache.write("products:user_1:abc:products", { data: "products" })
      Rails.cache.write("orders:user_1:def:orders", { data: "orders" })
      Rails.cache.write("users:user_1:ghi:users", { data: "users" })

      # Invalidate only products
      BetterService::CacheService.invalidate_for_context(user, :products)

      expect(Rails.cache.exist?("products:user_1:abc:products")).to be false
      expect(Rails.cache.exist?("orders:user_1:def:orders")).to be true
      expect(Rails.cache.exist?("users:user_1:ghi:users")).to be true
    end

    it "invalidate_for_user clears all contexts for user" do
      Rails.cache.write("products:user_1:abc:products", { data: "products" })
      Rails.cache.write("orders:user_1:def:orders", { data: "orders" })
      Rails.cache.write("products:user_2:ghi:products", { data: "other user" })

      BetterService::CacheService.invalidate_for_user(user)

      expect(Rails.cache.exist?("products:user_1:abc:products")).to be false
      expect(Rails.cache.exist?("orders:user_1:def:orders")).to be false
      expect(Rails.cache.exist?("products:user_2:ghi:products")).to be true
    end
  end

  describe "Cache key collision handling" do
    it "different services with same params have different cache keys" do
      counter_a = { count: 0 }
      counter_b = { count: 0 }

      service_a = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable
        cache_key :service_a
        cache_ttl 1.hour

        schema { optional(:id).maybe(:integer) }

        define_singleton_method(:counter) { counter_a }

        process_with do
          self.class.counter[:count] += 1
          { resource: { source: "A" } }
        end
      end

      service_b = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable
        cache_key :service_b
        cache_ttl 1.hour

        schema { optional(:id).maybe(:integer) }

        define_singleton_method(:counter) { counter_b }

        process_with do
          self.class.counter[:count] += 1
          { resource: { source: "B" } }
        end
      end

      resource_a, _ = service_a.new(user, params: { id: 1 }).call
      resource_b, _ = service_b.new(user, params: { id: 1 }).call

      expect(resource_a[:source]).to eq("A")
      expect(resource_b[:source]).to eq("B")
      expect(counter_a[:count]).to eq(1)
      expect(counter_b[:count]).to eq(1)
    end

    it "same service with different users have different cache keys" do
      counter = { count: 0 }

      service_class = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable
        cache_key :multi_user
        cache_ttl 1.hour

        schema { required(:id).filled(:integer) }

        define_singleton_method(:counter) { counter }

        process_with do
          self.class.counter[:count] += 1
          { resource: { fetched_at: Time.current.to_f } }
        end
      end

      resource1, _ = service_class.new(user, params: { id: 1 }).call
      resource2, _ = service_class.new(other_user, params: { id: 1 }).call

      # Both should execute independently (different users)
      expect(counter[:count]).to eq(2)
      expect(resource1[:fetched_at]).to be_present
      expect(resource2[:fetched_at]).to be_present
    end

    it "same params produce same cache key" do
      counter = { count: 0 }

      service_class = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::Cacheable
        cache_key :param_order_test
        cache_ttl 1.hour

        schema do
          optional(:a).maybe(:integer)
          optional(:b).maybe(:integer)
        end

        define_singleton_method(:counter) { counter }

        process_with do
          self.class.counter[:count] += 1
          { resource: { t: Time.current.to_f } }
        end
      end

      resource1, _ = service_class.new(user, params: { a: 1, b: 2 }).call
      resource2, _ = service_class.new(user, params: { a: 1, b: 2 }).call

      # Same params should hit cache
      expect(resource1[:t]).to eq(resource2[:t])
      expect(counter[:count]).to eq(1)
    end
  end
end
