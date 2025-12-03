# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Order::ShipService do
  include_context "with order"

  describe "#call" do
    context "shipping paid order as admin" do
      let(:service) do
        described_class.new(admin_user, params: {
          id: paid_order.id,
          tracking_number: "1Z999AA10123456784",
          carrier: "ups"
        })
      end
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "ships the order" do
        result
        paid_order.reload
        expect(paid_order.status).to eq("shipped")
      end

      it "includes shipping info in metadata" do
        expect(result.meta[:shipping_info][:tracking_number]).to eq("1Z999AA10123456784")
        expect(result.meta[:shipping_info][:carrier]).to eq("ups")
      end

      it "includes shipped action in metadata" do
        expect(result.meta[:action]).to eq(:shipped)
      end
    end

    context "shipping unpaid order" do
      let(:service) { described_class.new(admin_user, params: { id: order.id }) }

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:execution_error)
      end
    end

    context "as non-admin" do
      let(:service) { described_class.new(user, params: { id: paid_order.id }) }

      it_behaves_like "a service with authorization error"
    end

    context "with invalid carrier" do
      it "raises validation error" do
        expect {
          described_class.new(admin_user, params: {
            id: paid_order.id,
            carrier: "invalid_carrier"
          })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end
  end
end
