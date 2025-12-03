# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Order::CreateService do
  include_context "with products"

  let(:valid_params) do
    {
      items: [
        { product_id: product.id, quantity: 2 }
      ],
      payment_method: "credit_card"
    }
  end

  describe "#call" do
    context "with valid params" do
      let(:service) { described_class.new(user, params: valid_params) }
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "creates an order" do
        expect { service.call }.to change(Order, :count).by(1)
      end

      it "creates order items" do
        expect { service.call }.to change(OrderItem, :count).by(1)
      end

      it "calculates correct total" do
        expect(result.resource.total).to eq(product.price * 2)
      end

      it "sets order status to pending" do
        expect(result.resource.status).to eq("pending")
      end

      it "includes created action in metadata" do
        expect(result.meta[:action]).to eq(:created)
      end
    end

    context "with multiple items" do
      let(:product2) do
        Product.create!(
          name: "Second Product",
          price: 50.00,
          user: seller_user,
          published: true,
          stock: 20
        )
      end

      let(:service) do
        described_class.new(user, params: {
          items: [
            { product_id: product.id, quantity: 1 },
            { product_id: product2.id, quantity: 3 }
          ]
        })
      end

      it "creates multiple order items" do
        expect { service.call }.to change(OrderItem, :count).by(2)
      end

      it "calculates correct total for multiple items" do
        result = service.call
        expected_total = (product.price * 1) + (product2.price * 3)
        expect(result.resource.total).to eq(expected_total)
      end
    end

    context "with unpublished product" do
      let(:service) do
        described_class.new(user, params: {
          items: [ { product_id: unpublished_product.id, quantity: 1 } ]
        })
      end

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:validation_failed)
      end
    end

    context "with non-existent product" do
      let(:service) do
        described_class.new(user, params: {
          items: [ { product_id: 999999, quantity: 1 } ]
        })
      end

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:validation_failed)
      end
    end

    context "with empty items" do
      it "raises validation error" do
        expect {
          described_class.new(user, params: { items: [] })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end

    context "with invalid quantity" do
      it "raises validation error for zero quantity" do
        expect {
          described_class.new(user, params: {
            items: [ { product_id: product.id, quantity: 0 } ]
          })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end

      it "raises validation error for negative quantity" do
        expect {
          described_class.new(user, params: {
            items: [ { product_id: product.id, quantity: -1 } ]
          })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end

    context "with invalid payment method" do
      it "raises validation error" do
        expect {
          described_class.new(user, params: {
            items: [ { product_id: product.id, quantity: 1 } ],
            payment_method: "bitcoin"
          })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end
  end
end
