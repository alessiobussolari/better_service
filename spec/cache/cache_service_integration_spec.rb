# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe BetterService::CacheService, "Integration" do
  let(:user) { OpenStruct.new(id: 123) }
  let(:user2) { OpenStruct.new(id: 456) }

  before { Rails.cache.clear }
  after { Rails.cache.clear }

  describe "Direct Cache Key Invalidation" do
    it "invalidation removes actual cache entries created with Rails.cache" do
      Rails.cache.write("service:user_123:hash1:products", { data: "test1" })
      Rails.cache.write("service:user_123:hash2:products", { data: "test2" })
      Rails.cache.write("service:user_456:hash3:products", { data: "test3" })

      expect(Rails.cache.exist?("service:user_123:hash1:products")).to be true
      expect(Rails.cache.exist?("service:user_123:hash2:products")).to be true

      described_class.invalidate_for_context(user, "products")

      expect(Rails.cache.exist?("service:user_123:hash1:products")).to be false
      expect(Rails.cache.exist?("service:user_123:hash2:products")).to be false
      expect(Rails.cache.exist?("service:user_456:hash3:products")).to be true
    end

    it "global invalidation removes entries for all users" do
      Rails.cache.write("service:user_123:hash1:sidebar", { data: "u123" })
      Rails.cache.write("service:user_456:hash2:sidebar", { data: "u456" })
      Rails.cache.write("service:user_123:hash3:products", { data: "products" })

      described_class.invalidate_global("sidebar")

      expect(Rails.cache.exist?("service:user_123:hash1:sidebar")).to be false
      expect(Rails.cache.exist?("service:user_456:hash2:sidebar")).to be false
      expect(Rails.cache.exist?("service:user_123:hash3:products")).to be true
    end

    it "invalidate_for_user removes all user cache across contexts" do
      Rails.cache.write("service:user_123:hash1:products", { data: "p" })
      Rails.cache.write("service:user_123:hash2:sidebar", { data: "s" })
      Rails.cache.write("service:user_456:hash3:products", { data: "p2" })

      described_class.invalidate_for_user(user)

      expect(Rails.cache.exist?("service:user_123:hash1:products")).to be false
      expect(Rails.cache.exist?("service:user_123:hash2:sidebar")).to be false
      expect(Rails.cache.exist?("service:user_456:hash3:products")).to be true
    end
  end

  describe "Pattern Matching Accuracy" do
    it "invalidation matches wildcard patterns correctly" do
      Rails.cache.write("prefix:user_123:middle:products", { data: "match1" })
      Rails.cache.write("otherprefix:user_123:middle:products", { data: "match2" })
      Rails.cache.write("prefix:user_456:middle:products", { data: "nomatch" })

      described_class.invalidate_for_context(user, "products")

      expect(Rails.cache.exist?("prefix:user_123:middle:products")).to be false
      expect(Rails.cache.exist?("otherprefix:user_123:middle:products")).to be false
      expect(Rails.cache.exist?("prefix:user_456:middle:products")).to be true
    end

    it "context invalidation is case sensitive" do
      Rails.cache.write("service:user_123:hash:products", { data: "lowercase" })
      Rails.cache.write("service:user_123:hash:Products", { data: "uppercase" })

      described_class.invalidate_for_context(user, "products")

      expect(Rails.cache.exist?("service:user_123:hash:products")).to be false
      expect(Rails.cache.exist?("service:user_123:hash:Products")).to be true
    end
  end

  describe "Clear All Functionality" do
    it "removes all BetterService patterned cache" do
      Rails.cache.write("anything:user_123:hash:products", { data: "1" })
      Rails.cache.write("other:user_456:hash:sidebar", { data: "2" })
      Rails.cache.write("app:user_789:hash:dashboard", { data: "3" })
      Rails.cache.write("non_pattern_key", { data: "should_remain" })

      described_class.clear_all

      expect(Rails.cache.exist?("anything:user_123:hash:products")).to be false
      expect(Rails.cache.exist?("other:user_456:hash:sidebar")).to be false
      expect(Rails.cache.exist?("app:user_789:hash:dashboard")).to be false
      expect(Rails.cache.exist?("non_pattern_key")).to be true
    end
  end

  describe "Multiple Users Same Context" do
    it "user-specific invalidation does not affect other users in same context" do
      Rails.cache.write("service:user_123:hash1:products", { data: "u123" })
      Rails.cache.write("service:user_456:hash2:products", { data: "u456" })

      described_class.invalidate_for_context(user, "products")

      expect(Rails.cache.exist?("service:user_123:hash1:products")).to be false
      expect(Rails.cache.exist?("service:user_456:hash2:products")).to be true
    end

    it "global invalidation affects all users in context" do
      Rails.cache.write("service:user_123:hash1:products", { data: "u123" })
      Rails.cache.write("service:user_456:hash2:products", { data: "u456" })
      Rails.cache.write("service:user_789:hash3:products", { data: "u789" })

      described_class.invalidate_global("products")

      expect(Rails.cache.exist?("service:user_123:hash1:products")).to be false
      expect(Rails.cache.exist?("service:user_456:hash2:products")).to be false
      expect(Rails.cache.exist?("service:user_789:hash3:products")).to be false
    end
  end

  describe "User Across Multiple Contexts" do
    it "invalidating one context leaves others" do
      Rails.cache.write("service:user_123:hash1:products", { data: "p" })
      Rails.cache.write("service:user_123:hash2:orders", { data: "o" })
      Rails.cache.write("service:user_123:hash3:sidebar", { data: "s" })

      described_class.invalidate_for_context(user, "products")

      expect(Rails.cache.exist?("service:user_123:hash1:products")).to be false
      expect(Rails.cache.exist?("service:user_123:hash2:orders")).to be true
      expect(Rails.cache.exist?("service:user_123:hash3:sidebar")).to be true
    end
  end

  describe "Special Characters in Context" do
    it "context names with colons are handled correctly" do
      context_with_colon = "admin:settings"
      Rails.cache.write("service:user_123:hash:admin:settings", { data: "test" })

      described_class.invalidate_for_context(user, context_with_colon)

      expect(Rails.cache.exist?("service:user_123:hash:admin:settings")).to be false
    end
  end

  describe "Boundary Conditions" do
    it "invalidation with no matching entries completes successfully" do
      expect {
        count = described_class.invalidate_for_context(user, "nonexistent")
        expect(count).to be_kind_of(Integer)
      }.not_to raise_error
    end

    it "multiple sequential invalidations work correctly" do
      Rails.cache.write("service:user_123:hash1:products", { data: "1" })
      Rails.cache.write("service:user_123:hash2:orders", { data: "2" })

      described_class.invalidate_for_context(user, "products")
      expect(Rails.cache.exist?("service:user_123:hash1:products")).to be false
      expect(Rails.cache.exist?("service:user_123:hash2:orders")).to be true

      described_class.invalidate_for_context(user, "orders")
      expect(Rails.cache.exist?("service:user_123:hash2:orders")).to be false
    end
  end
end
