# frozen_string_literal: true

require "spec_helper"

RSpec.describe Payment::Stripe::ChargeService do
  include_context "with payment"

  let(:stripe_payment) do
    Payment.create!(
      order: order,
      amount: order.total,
      provider: :stripe,
      status: :processing
    )
  end

  describe "#call" do
    context "with valid processing payment" do
      let(:service) do
        described_class.new(user, params: {
          payment_id: stripe_payment.id,
          card_token: "tok_visa"
        })
      end
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "completes the payment" do
        result
        stripe_payment.reload
        expect(stripe_payment.status).to eq("completed")
      end

      it "sets transaction_id" do
        result
        stripe_payment.reload
        expect(stripe_payment.transaction_id).to start_with("ch_")
      end

      it "sets completed_at" do
        result
        stripe_payment.reload
        expect(stripe_payment.completed_at).to be_present
      end

      # Note: Order status is updated by Order::ConfirmService in the workflow
      # The charge service only completes the payment

      it "returns stripe charge id" do
        expect(result.resource.transaction_id).to start_with("ch_")
      end
    end

    context "with pending payment" do
      let(:pending_stripe) do
        Payment.create!(
          order: order,
          amount: order.total,
          provider: :stripe,
          status: :pending
        )
      end
      let(:service) do
        described_class.new(user, params: { payment_id: pending_stripe.id })
      end

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:execution_error)
      end
    end

    context "with wrong provider" do
      let(:paypal_payment) do
        Payment.create!(
          order: confirmed_order,
          amount: confirmed_order.total,
          provider: :paypal,
          status: :processing
        )
      end
      let(:service) do
        described_class.new(user, params: { payment_id: paypal_payment.id })
      end

      it "returns a failure result for wrong provider" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:execution_error)
      end
    end

    context "as admin" do
      let(:service) do
        described_class.new(admin_user, params: { payment_id: stripe_payment.id })
      end

      it "allows admin to charge" do
        result = service.call
        expect(result.success?).to be true
      end
    end

    context "as non-owner" do
      let(:other_user) { User.create!(name: "Other", email: "other@example.com") }
      let(:service) do
        described_class.new(other_user, params: { payment_id: stripe_payment.id })
      end

      it_behaves_like "a service with authorization error"
    end
  end
end
