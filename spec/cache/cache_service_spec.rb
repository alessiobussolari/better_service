# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe BetterService::CacheService do
  let(:user) { OpenStruct.new(id: 123) }
  let(:context_name) { "products" }

  before { Rails.cache.clear }
  after { Rails.cache.clear }

  describe ".invalidate_for_context" do
    it "accepts user and context parameters" do
      result = described_class.invalidate_for_context(user, "products")
      expect(result).to be_instance_of(Integer).or be_instance_of(Array)
    end

    it "accepts integer user id" do
      result = described_class.invalidate_for_context(999, "products")
      expect(result).to be_instance_of(Integer).or be_instance_of(Array)
    end

    it "returns 0 when user is nil" do
      count = described_class.invalidate_for_context(nil, "products")
      expect(count).to eq(0)
    end

    it "returns 0 when context is nil" do
      count = described_class.invalidate_for_context(user, nil)
      expect(count).to eq(0)
    end

    it "returns 0 with empty string context" do
      count = described_class.invalidate_for_context(user, "")
      expect(count).to eq(0)
    end

    it "handles whitespace context" do
      result = described_class.invalidate_for_context(user, "   ")
      expect(result).to be_instance_of(Integer).or be_instance_of(Array)
    end

    it "actually deletes matching cache entries" do
      Rails.cache.write("products_index:user_123:abc123:products", { data: "product 1" })
      Rails.cache.write("products_index:user_123:def456:products", { data: "product 2" })
      Rails.cache.write("products_index:user_456:ghi789:products", { data: "other user" })
      Rails.cache.write("sidebar:user_123:jkl012:sidebar", { data: "sidebar" })

      expect(Rails.cache.exist?("products_index:user_123:abc123:products")).to be true

      described_class.invalidate_for_context(user, "products")

      expect(Rails.cache.exist?("products_index:user_123:abc123:products")).to be false
      expect(Rails.cache.exist?("products_index:user_123:def456:products")).to be false
      expect(Rails.cache.exist?("products_index:user_456:ghi789:products")).to be true
      expect(Rails.cache.exist?("sidebar:user_123:jkl012:sidebar")).to be true
    end
  end

  describe ".invalidate_global" do
    it "accepts context parameter" do
      result = described_class.invalidate_global("sidebar")
      expect(result).to be_instance_of(Integer).or be_instance_of(Array)
    end

    it "returns 0 when context is nil" do
      count = described_class.invalidate_global(nil)
      expect(count).to eq(0)
    end

    it "returns 0 with empty string context" do
      count = described_class.invalidate_global("")
      expect(count).to eq(0)
    end

    it "actually deletes all cache entries for context" do
      Rails.cache.write("sidebar:user_123:abc:sidebar", { data: "user 123 sidebar" })
      Rails.cache.write("sidebar:user_456:def:sidebar", { data: "user 456 sidebar" })
      Rails.cache.write("sidebar:user_789:ghi:sidebar", { data: "user 789 sidebar" })
      Rails.cache.write("products_index:user_123:xyz:products", { data: "products" })

      described_class.invalidate_global("sidebar")

      expect(Rails.cache.exist?("sidebar:user_123:abc:sidebar")).to be false
      expect(Rails.cache.exist?("sidebar:user_456:def:sidebar")).to be false
      expect(Rails.cache.exist?("sidebar:user_789:ghi:sidebar")).to be false
      expect(Rails.cache.exist?("products_index:user_123:xyz:products")).to be true
    end
  end

  describe ".invalidate_for_user" do
    it "accepts user parameter" do
      result = described_class.invalidate_for_user(user)
      expect(result).to be_instance_of(Integer).or be_instance_of(Array)
    end

    it "accepts integer user id" do
      result = described_class.invalidate_for_user(789)
      expect(result).to be_instance_of(Integer).or be_instance_of(Array)
    end

    it "returns 0 when user is nil" do
      count = described_class.invalidate_for_user(nil)
      expect(count).to eq(0)
    end

    it "actually deletes all cache for specific user" do
      Rails.cache.write("products_index:user_123:abc:products", { data: "products" })
      Rails.cache.write("sidebar:user_123:def:sidebar", { data: "sidebar" })
      Rails.cache.write("dashboard:user_123:ghi:dashboard", { data: "dashboard" })
      Rails.cache.write("products_index:user_456:abc:products", { data: "other user" })

      described_class.invalidate_for_user(user)

      expect(Rails.cache.exist?("products_index:user_123:abc:products")).to be false
      expect(Rails.cache.exist?("sidebar:user_123:def:sidebar")).to be false
      expect(Rails.cache.exist?("dashboard:user_123:ghi:dashboard")).to be false
      expect(Rails.cache.exist?("products_index:user_456:abc:products")).to be true
    end
  end

  describe ".invalidate_key" do
    it "removes specific cache key" do
      key = "test_key_123"
      Rails.cache.write(key, { data: "test" })
      expect(Rails.cache.exist?(key)).to be true

      result = described_class.invalidate_key(key)

      expect(Rails.cache.exist?(key)).to be false
      expect(result).to be true
    end

    it "returns false when key is nil" do
      result = described_class.invalidate_key(nil)
      expect(result).to eq(false)
    end

    it "returns true for non-existent key" do
      result = described_class.invalidate_key("non_existent_key_xyz")
      expect(result).to eq(true)
    end

    it "returns false with empty string" do
      result = described_class.invalidate_key("")
      expect(result).to eq(false)
    end
  end

  describe ".clear_all" do
    it "returns result" do
      result = described_class.clear_all
      expect(result).to be_instance_of(Integer).or be_instance_of(Array)
    end

    it "actually removes all BetterService cache" do
      Rails.cache.write("products_index:user_123:abc:products", { data: "products" })
      Rails.cache.write("sidebar:user_456:def:sidebar", { data: "sidebar" })
      Rails.cache.write("dashboard:user_789:ghi:dashboard", { data: "dashboard" })

      described_class.clear_all

      expect(Rails.cache.exist?("products_index:user_123:abc:products")).to be false
      expect(Rails.cache.exist?("sidebar:user_456:def:sidebar")).to be false
      expect(Rails.cache.exist?("dashboard:user_789:ghi:dashboard")).to be false
    end
  end

  describe ".fetch" do
    it "returns cached value if exists" do
      key = "test_key"
      cached_value = { data: "cached" }
      Rails.cache.write(key, cached_value)

      result = described_class.fetch(key) { { data: "fresh" } }

      expect(result).to eq(cached_value)
    end

    it "executes block and caches result if key missing" do
      key = "test_key_fetch_new"
      fresh_value = { data: "fresh" }

      result = described_class.fetch(key) { fresh_value }

      expect(result).to eq(fresh_value)
      expect(Rails.cache.read(key)).to eq(fresh_value)
    end

    it "respects expires_in option" do
      key = "test_key_expires"
      value = { data: "test" }

      result = described_class.fetch(key, expires_in: 1.hour) { value }

      expect(result).to eq(value)
      expect(Rails.cache.read(key)).to eq(value)
    end

    it "respects force option" do
      key = "test_key_force"
      Rails.cache.write(key, { data: "old" })

      result = described_class.fetch(key, force: true) { { data: "new" } }

      expect(result).to eq({ data: "new" })
    end

    it "handles nil value returned by block" do
      key = "test_key_nil_value"

      result = described_class.fetch(key) { nil }

      expect(result).to be_nil

      execution_count = 0
      result2 = described_class.fetch(key) do
        execution_count += 1
        "should not execute"
      end

      expect(result2).to be_nil
      expect(execution_count).to eq(0)
    end

    it "handles exception in block" do
      key = "test_key_exception"

      expect {
        described_class.fetch(key) { raise StandardError, "Block error" }
      }.to raise_error(StandardError, "Block error")

      expect(Rails.cache.exist?(key)).to be false
    end

    it "handles multiple options" do
      key = "test_key_multi_options"
      value = { data: "test" }

      result = described_class.fetch(key, expires_in: 1.hour, race_condition_ttl: 10) { value }

      expect(result).to eq(value)
      expect(Rails.cache.exist?(key)).to be true
    end
  end

  describe ".exist?" do
    it "returns true when key exists" do
      key = "test_key_exist"
      Rails.cache.write(key, { data: "test" })

      expect(described_class.exist?(key)).to be true
    end

    it "returns false when key does not exist" do
      expect(described_class.exist?("nonexistent_key_12345")).to be false
    end

    it "returns false after invalidation" do
      key = "test_key_invalidation"
      Rails.cache.write(key, { data: "test" })
      expect(described_class.exist?(key)).to be true

      described_class.invalidate_key(key)
      expect(described_class.exist?(key)).to be false
    end

    it "returns false with nil key" do
      expect(described_class.exist?(nil)).to be false
    end

    it "works with key containing special characters" do
      key = "test:key:with:colons"
      Rails.cache.write(key, { data: "test" })

      expect(described_class.exist?(key)).to be true
    end
  end

  describe ".stats" do
    it "returns cache store information" do
      stats = described_class.stats

      expect(stats).to have_key(:cache_store)
      expect(stats).to have_key(:supports_pattern_deletion)
      expect(stats).to have_key(:supports_async)

      expect(stats[:cache_store]).not_to be_nil
      expect([ true, false ]).to include(stats[:supports_pattern_deletion])
      expect([ true, false ]).to include(stats[:supports_async])
    end

    it "reflects actual cache store class" do
      stats = described_class.stats
      expect(stats[:cache_store]).to eq(Rails.cache.class.name)
    end

    it "shows pattern deletion support correctly" do
      stats = described_class.stats
      expected_support = Rails.cache.respond_to?(:delete_matched)
      expect(stats[:supports_pattern_deletion]).to eq(expected_support)
    end
  end

  describe "private pattern building methods" do
    describe "#build_user_context_pattern" do
      it "creates correct pattern" do
        pattern = described_class.send(:build_user_context_pattern, user, "products")
        expect(pattern).to eq("*:user_123:*:products")
      end

      it "handles integer user id" do
        pattern = described_class.send(:build_user_context_pattern, 456, "sidebar")
        expect(pattern).to eq("*:user_456:*:sidebar")
      end

      it "handles string user id" do
        user_with_string_id = OpenStruct.new(id: "abc123")
        pattern = described_class.send(:build_user_context_pattern, user_with_string_id, "products")
        expect(pattern).to eq("*:user_abc123:*:products")
      end
    end

    describe "#build_global_context_pattern" do
      it "creates correct pattern" do
        pattern = described_class.send(:build_global_context_pattern, "dashboard")
        expect(pattern).to eq("*:dashboard")
      end

      it "handles context with special characters" do
        pattern = described_class.send(:build_global_context_pattern, "admin:settings")
        expect(pattern).to eq("*:admin:settings")
      end
    end

    describe "#build_user_pattern" do
      it "creates correct pattern" do
        pattern = described_class.send(:build_user_pattern, user)
        expect(pattern).to eq("*:user_123:*")
      end

      it "handles integer user id" do
        pattern = described_class.send(:build_user_pattern, 789)
        expect(pattern).to eq("*:user_789:*")
      end

      it "handles zero id" do
        user_with_zero_id = OpenStruct.new(id: 0)
        pattern = described_class.send(:build_user_pattern, user_with_zero_id)
        expect(pattern).to eq("*:user_0:*")
      end

      it "handles nil id" do
        user_with_nil_id = OpenStruct.new(id: nil)
        pattern = described_class.send(:build_user_pattern, user_with_nil_id)
        expect(pattern).to eq("*:user_:*")
      end
    end
  end

  describe "cache store compatibility" do
    it "supports_delete_matched? returns boolean" do
      result = described_class.send(:supports_delete_matched?)
      expect([ true, false ]).to include(result)
    end

    it "supports_delete_matched? returns true for MemoryStore" do
      expect(described_class.send(:supports_delete_matched?)).to be true
    end
  end

  describe "non-matching entries preservation" do
    it "does not delete non-matching entries" do
      Rails.cache.write("products_index:user_123:abc:products", { data: "target" })
      Rails.cache.write("products_index:user_456:def:products", { data: "different user" })
      Rails.cache.write("sidebar:user_123:ghi:sidebar", { data: "different context" })
      Rails.cache.write("unrelated_key", { data: "unrelated" })

      described_class.invalidate_for_context(user, "products")

      expect(Rails.cache.exist?("products_index:user_123:abc:products")).to be false
      expect(Rails.cache.exist?("products_index:user_456:def:products")).to be true
      expect(Rails.cache.exist?("sidebar:user_123:ghi:sidebar")).to be true
      expect(Rails.cache.exist?("unrelated_key")).to be true
    end
  end

  describe "multiple users and contexts" do
    it "invalidation works correctly with multiple users sharing same context" do
      Rails.cache.write("products:user_123:abc:products", { data: "user 123 products" })
      Rails.cache.write("products:user_456:def:products", { data: "user 456 products" })

      described_class.invalidate_for_context(user, "products")

      expect(Rails.cache.exist?("products:user_123:abc:products")).to be false
      expect(Rails.cache.exist?("products:user_456:def:products")).to be true
    end

    it "invalidation works with user across multiple contexts" do
      Rails.cache.write("products:user_123:abc:products", { data: "products" })
      Rails.cache.write("orders:user_123:def:orders", { data: "orders" })
      Rails.cache.write("sidebar:user_123:ghi:sidebar", { data: "sidebar" })

      described_class.invalidate_for_context(user, "products")

      expect(Rails.cache.exist?("products:user_123:abc:products")).to be false
      expect(Rails.cache.exist?("orders:user_123:def:orders")).to be true
      expect(Rails.cache.exist?("sidebar:user_123:ghi:sidebar")).to be true
    end
  end

  describe "logging" do
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

    it "logs invalidation count for invalidate_for_context" do
      Rails.cache.write("products:user_123:abc:products", { data: "test" })

      log_output = capture_log_output do
        described_class.invalidate_for_context(user, "products")
      end

      expect(log_output).to match(/BetterService::CacheService/)
      expect(log_output).to match(/Invalidated/)
    end

    it "logs invalidation for invalidate_global" do
      Rails.cache.write("sidebar:user_123:abc:sidebar", { data: "test" })

      log_output = capture_log_output do
        described_class.invalidate_global("sidebar")
      end

      expect(log_output).to match(/BetterService::CacheService/)
      expect(log_output).to match(/Invalidated/)
    end

    it "handles nil Rails.logger gracefully" do
      original_logger = Rails.logger
      Rails.logger = nil

      expect {
        described_class.invalidate_for_context(user, "products")
      }.not_to raise_error
    ensure
      Rails.logger = original_logger
    end
  end
end
