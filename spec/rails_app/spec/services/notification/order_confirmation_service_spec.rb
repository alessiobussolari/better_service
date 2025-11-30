# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notification::OrderConfirmationService do
  include_context "with order"

  describe "#call" do
    context "sending confirmation for existing order" do
      let(:service) do
        described_class.new(user, params: {
          order_id: order.id,
          email: "customer@example.com"
        })
      end
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "returns the order" do
        expect(result.resource[:order]).to eq(order)
      end

      it "returns notification details" do
        expect(result.resource[:notification]).to be_present
        expect(result.resource[:notification][:type]).to eq(:email)
        expect(result.resource[:notification][:to]).to eq("customer@example.com")
      end

      it "includes order id in subject" do
        expect(result.resource[:notification][:subject]).to include(order.id.to_s)
      end

      it "includes sent action in metadata" do
        expect(result.meta[:action]).to eq(:sent)
      end
    end

    context "with non-existent order" do
      let(:service) do
        described_class.new(user, params: {
          order_id: 999999,
          email: "customer@example.com"
        })
      end

      it_behaves_like "a service with resource not found error"
    end

    context "with invalid params" do
      it "raises validation error for missing order_id" do
        expect {
          described_class.new(user, params: { email: "test@example.com" })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end

      it "raises validation error for missing email" do
        expect {
          described_class.new(user, params: { order_id: order.id })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end

    context "sending for order with payment" do
      let(:service) do
        described_class.new(user, params: {
          order_id: paid_order.id,
          email: "customer@example.com"
        })
      end
      let(:result) { service.call }

      it "includes payment info in order" do
        expect(result.resource[:order].payment).to be_present
      end
    end
  end
end
