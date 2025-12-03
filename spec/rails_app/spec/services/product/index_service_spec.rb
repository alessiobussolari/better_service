# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Product::IndexService do
  include_context "with products"

  describe "#call" do
    context "with valid params" do
      # Use seller_user since products belong to seller_user
      let(:service) { described_class.new(seller_user, params: {}) }
      let(:result) { service.call }

      before { product } # create products

      it_behaves_like "a successful service"

      it "returns user's products" do
        expect(result.resource.map(&:object)).to include(product)
      end

      it "includes unpublished products (owner can see all)" do
        unpublished_product # create unpublished product
        # Clear cache to ensure fresh query
        Rails.cache.clear
        result2 = described_class.new(seller_user, params: {}).call
        expect(result2.resource.map(&:object)).to include(unpublished_product)
      end

      it "includes metadata with action" do
        expect(result.meta[:action]).to eq(:listed)
      end
    end

    context "with pagination params" do
      let(:service) { described_class.new(seller_user, params: { page: 1, per_page: 10 }) }
      let(:result) { service.call }

      it "returns paginated results" do
        product
        expect(result.success?).to be true
      end
    end

    context "with search query" do
      let(:service) { described_class.new(seller_user, params: { search: "Test" }) }
      let(:result) { service.call }

      it "filters by search query" do
        product
        expect(result.resource.map { |p| p.object.name }).to include("Test Product")
      end
    end

    context "with invalid params" do
      it "raises validation error for invalid page" do
        expect {
          described_class.new(user, params: { page: -1 })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end
  end
end
