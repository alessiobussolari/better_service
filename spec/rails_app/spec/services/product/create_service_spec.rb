# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Product::CreateService do
  include_context "with user"

  let(:valid_params) do
    {
      name: "New Product",
      price: 149.99,
      description: "A great product"
    }
  end

  describe "#call" do
    context "as seller" do
      let(:service) { described_class.new(seller_user, params: valid_params) }
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "creates a product" do
        expect { service.call }.to change(Product, :count).by(1)
      end

      it "returns the created product" do
        expect(result.resource.name).to eq("New Product")
      end

      it "assigns product to current user" do
        expect(result.resource.user).to eq(seller_user)
      end

      it "includes created action in metadata" do
        expect(result.meta[:action]).to eq(:created)
      end

      it "uses I18n message" do
        expect(result.message).to include("New Product")
      end
    end

    context "as admin" do
      let(:service) { described_class.new(admin_user, params: valid_params) }
      let(:result) { service.call }

      it "allows admin to create products" do
        expect(result.success?).to be true
      end
    end

    context "as regular user" do
      let(:service) { described_class.new(user, params: valid_params) }

      it_behaves_like "a service with authorization error"
    end

    context "with missing required fields" do
      it "raises validation error for missing name" do
        expect {
          described_class.new(seller_user, params: { price: 99.99 })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end

      it "raises validation error for missing price" do
        expect {
          described_class.new(seller_user, params: { name: "Test" })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end

    context "with invalid price" do
      it "raises validation error for negative price" do
        expect {
          described_class.new(seller_user, params: { name: "Test", price: -10 })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end
  end
end
