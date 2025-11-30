# frozen_string_literal: true

require "spec_helper"

RSpec.describe Inventory::ReserveService do
  include_context "with order"

  describe "#call" do
    context "reserving available stock" do
      let(:service) { described_class.new(user, params: { order_id: order.id }) }
      let(:result) { service.call }

      before do
        product.update!(stock: 100)
      end

      it_behaves_like "a successful service"

      it "decreases product stock" do
        original_stock = product.stock
        result
        product.reload
        expected_stock = original_stock - order.order_items.first.quantity
        expect(product.stock).to eq(expected_stock)
      end

      it "returns reserved items info" do
        expect(result.resource[:reserved_items]).to be_present
        expect(result.resource[:reserved_items].first[:product_id]).to eq(product.id)
      end

      it "includes reserved action in metadata" do
        expect(result.meta[:action]).to eq(:reserved)
      end
    end

    context "with insufficient stock" do
      let(:service) { described_class.new(user, params: { order_id: order.id }) }

      before do
        product.update!(stock: 1)
        order.order_items.first.update!(quantity: 10)
      end

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:execution_error)
      end
    end

    context "with non-existent order" do
      let(:service) { described_class.new(user, params: { order_id: 999999 }) }

      it_behaves_like "a service with resource not found error"
    end
  end
end
