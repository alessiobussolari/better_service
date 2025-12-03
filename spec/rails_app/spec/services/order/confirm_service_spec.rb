# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Order::ConfirmService do
  include_context "with order"

  describe "#call" do
    context "confirming pending order as admin" do
      let(:service) { described_class.new(admin_user, params: { id: order.id }) }
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "confirms the order" do
        result
        order.reload
        expect(order.status).to eq("confirmed")
      end

      it "includes confirmed action in metadata" do
        expect(result.meta[:action]).to eq(:confirmed)
      end
    end

    context "confirming already confirmed order" do
      let(:service) { described_class.new(admin_user, params: { id: confirmed_order.id }) }

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:execution_error)
      end
    end

    context "as non-admin" do
      let(:service) { described_class.new(user, params: { id: order.id }) }

      it_behaves_like "a service with authorization error"
    end
  end
end
