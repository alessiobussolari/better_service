# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Product::ShowService do
  include_context "with products"

  describe "#call" do
    context "with valid id" do
      let(:service) { described_class.new(user, params: { id: product.id }) }
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "returns the product presenter" do
        expect(result.resource).to be_a(ProductPresenter)
        expect(result.resource.object).to eq(product)
      end

      it "includes show action in metadata" do
        expect(result.meta[:action]).to eq(:showed)
      end
    end

    context "with non-existent id" do
      # Use admin_user since they can view any product (even non-existent - will get "not found")
      let(:service) { described_class.new(admin_user, params: { id: 999999 }) }

      it_behaves_like "a service with resource not found error"
    end

    context "with missing id" do
      it "raises validation error" do
        expect {
          described_class.new(user, params: {})
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end
  end
end
