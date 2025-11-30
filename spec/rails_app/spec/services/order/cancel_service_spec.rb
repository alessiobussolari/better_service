# frozen_string_literal: true

require "spec_helper"

RSpec.describe Order::CancelService do
  include_context "with order"

  describe "#call" do
    context "cancelling pending order as owner" do
      let(:service) { described_class.new(user, params: { id: order.id }) }
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "cancels the order" do
        result
        order.reload
        expect(order.status).to eq("cancelled")
      end

      it "includes cancelled action in metadata" do
        expect(result.meta[:action]).to eq(:cancelled)
      end
    end

    context "cancelling confirmed order as owner" do
      let(:service) { described_class.new(user, params: { id: confirmed_order.id }) }
      let(:result) { service.call }

      it "allows cancelling confirmed orders" do
        expect(result.success?).to be true
        confirmed_order.reload
        expect(confirmed_order.status).to eq("cancelled")
      end
    end

    context "cancelling paid order" do
      let(:service) { described_class.new(user, params: { id: paid_order.id }) }

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:execution_error)
      end
    end

    context "as admin" do
      let(:service) { described_class.new(admin_user, params: { id: order.id }) }

      it "allows admin to cancel any order" do
        result = service.call
        expect(result.success?).to be true
      end
    end

    context "as non-owner" do
      let(:other_user) { User.create!(name: "Other", email: "other@example.com") }
      let(:service) { described_class.new(other_user, params: { id: order.id }) }

      it_behaves_like "a service with authorization error"
    end

    context "with reason" do
      let(:service) do
        described_class.new(user, params: { id: order.id, reason: "Changed my mind" })
      end

      it "accepts cancellation reason" do
        result = service.call
        expect(result.success?).to be true
      end
    end
  end
end
