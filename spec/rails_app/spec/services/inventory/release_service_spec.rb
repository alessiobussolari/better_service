# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Inventory::ReleaseService do
  include_context "with order"

  describe "#call" do
    context "releasing reserved stock" do
      let(:service) { described_class.new(user, params: { order_id: order.id }) }
      let(:result) { service.call }

      before do
        product.update!(stock: 50)
      end

      it_behaves_like "a successful service"

      it "increases product stock" do
        original_stock = product.stock
        quantity = order.order_items.first.quantity
        result
        product.reload
        expect(product.stock).to eq(original_stock + quantity)
      end

      it "returns released items info" do
        expect(result.resource[:released_items]).to be_present
        expect(result.resource[:released_items].first[:product_id]).to eq(product.id)
      end

      it "includes released action in metadata" do
        expect(result.meta[:action]).to eq(:released)
      end
    end

    context "with non-existent order" do
      let(:service) { described_class.new(user, params: { order_id: 999999 }) }

      it_behaves_like "a service with resource not found error"
    end
  end
end
