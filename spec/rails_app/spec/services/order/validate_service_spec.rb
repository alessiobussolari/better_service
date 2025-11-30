# frozen_string_literal: true

require "spec_helper"

RSpec.describe Order::ValidateService do
  include_context "with order"

  describe "#call" do
    context "validating a pending order with items" do
      let(:service) { described_class.new(user, params: { id: order.id }) }
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "returns the order" do
        expect(result.resource).to eq(order)
      end

      it "includes validated action in metadata" do
        expect(result.meta[:action]).to eq(:validated)
      end
    end

    context "as admin" do
      let(:service) { described_class.new(admin_user, params: { id: order.id }) }
      let(:result) { service.call }

      it "allows admin to validate" do
        expect(result.success?).to be true
      end
    end

    context "with non-pending order" do
      let(:service) { described_class.new(user, params: { id: confirmed_order.id }) }

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:execution_error)
      end
    end

    context "with order without items" do
      let(:empty_order) do
        Order.create!(user: user, total: 10.00, status: :pending, payment_method: :credit_card)
        # Note: Order has no items, just minimum valid total
      end
      let(:service) { described_class.new(user, params: { id: empty_order.id }) }

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:validation_failed)
      end
    end

    context "with unpublished product in order" do
      before do
        product.update!(published: false)
      end

      let(:service) { described_class.new(user, params: { id: order.id }) }

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:validation_failed)
      end
    end

    context "as non-owner" do
      let(:other_user) { User.create!(name: "Other", email: "other@example.com") }
      let(:service) { described_class.new(other_user, params: { id: order.id }) }

      it_behaves_like "a service with authorization error"
    end

    context "with non-existent order" do
      let(:service) { described_class.new(admin_user, params: { id: 999999 }) }

      it_behaves_like "a service with resource not found error"
    end
  end
end
