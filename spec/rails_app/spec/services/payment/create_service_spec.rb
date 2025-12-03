# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Payment::CreateService do
  include_context "with order"

  describe "#call" do
    context "creating stripe payment as owner" do
      let(:service) do
        described_class.new(user, params: {
          order_id: order.id,
          provider: "stripe"
        })
      end
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "creates a payment" do
        expect { service.call }.to change(Payment, :count).by(1)
      end

      it "sets correct provider" do
        expect(result.resource.provider).to eq("stripe")
      end

      it "sets amount from order total" do
        expect(result.resource.amount).to eq(order.total)
      end

      it "sets status to pending" do
        expect(result.resource.status).to eq("pending")
      end
    end

    context "creating paypal payment" do
      let(:service) do
        described_class.new(user, params: {
          order_id: order.id,
          provider: "paypal"
        })
      end
      let(:result) { service.call }

      it "creates paypal payment" do
        expect(result.resource.provider).to eq("paypal")
      end
    end

    context "creating bank payment" do
      let(:service) do
        described_class.new(user, params: {
          order_id: order.id,
          provider: "bank"
        })
      end
      let(:result) { service.call }

      it "creates bank payment" do
        expect(result.resource.provider).to eq("bank")
      end
    end

    context "when payment already exists" do
      before do
        Payment.create!(
          order: order,
          amount: order.total,
          provider: :stripe,
          status: :pending
        )
      end

      let(:service) do
        described_class.new(user, params: {
          order_id: order.id,
          provider: "stripe"
        })
      end

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:execution_error)
      end
    end

    context "as admin" do
      let(:service) do
        described_class.new(admin_user, params: {
          order_id: order.id,
          provider: "stripe"
        })
      end

      it "allows admin to create payment" do
        result = service.call
        expect(result.success?).to be true
      end
    end

    context "as non-owner" do
      let(:other_user) { User.create!(name: "Other", email: "other@example.com") }
      let(:service) do
        described_class.new(other_user, params: {
          order_id: order.id,
          provider: "stripe"
        })
      end

      it_behaves_like "a service with authorization error"
    end

    context "with invalid provider" do
      it "raises validation error" do
        expect {
          described_class.new(user, params: {
            order_id: order.id,
            provider: "bitcoin"
          })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end
  end
end
