# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Order::UpdateService do
  include_context "with order"

  describe "#call" do
    context "as owner with pending order" do
      let(:service) do
        described_class.new(user, params: {
          id: order.id,
          payment_method: "paypal"
        })
      end
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "updates the payment method" do
        result
        order.reload
        expect(order.payment_method).to eq("paypal")
      end

      it "includes updated action in metadata" do
        expect(result.meta[:action]).to eq(:updated)
      end
    end

    context "as non-owner" do
      let(:other_user) { User.create!(name: "Other", email: "other@example.com") }
      let(:service) do
        described_class.new(other_user, params: { id: order.id, payment_method: "paypal" })
      end

      it_behaves_like "a service with authorization error"
    end

    context "with non-pending order" do
      let(:service) do
        described_class.new(user, params: { id: confirmed_order.id, payment_method: "paypal" })
      end

      it "returns authorization error (order must be pending)" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:unauthorized)
      end
    end

    context "with non-existent order" do
      let(:service) do
        described_class.new(admin_user, params: { id: 999999, payment_method: "paypal" })
      end

      it "returns authorization error" do
        result = service.call
        expect(result.success?).to be false
      end
    end

    context "with invalid params" do
      it "raises validation error for missing id" do
        expect {
          described_class.new(user, params: { payment_method: "paypal" })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end

      it "raises validation error for invalid payment method" do
        expect {
          described_class.new(user, params: { id: order.id, payment_method: "bitcoin" })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end
  end
end
