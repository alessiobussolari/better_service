# frozen_string_literal: true

require_relative "../../../spec_helper"

RSpec.describe Payment::Paypal::ChargeService do
  include_context "with order"

  let(:paypal_payment) do
    Payment.create!(
      order: order,
      amount: order.total,
      provider: :paypal,
      status: :processing
    )
  end

  describe "#call" do
    context "with valid processing payment" do
      let(:service) do
        described_class.new(user, params: {
          payment_id: paypal_payment.id,
          paypal_order_id: "PP-ORDER-123"
        })
      end
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "completes the payment" do
        result
        paypal_payment.reload
        expect(paypal_payment.status).to eq("completed")
      end

      it "sets transaction_id with PAY prefix" do
        result
        paypal_payment.reload
        expect(paypal_payment.transaction_id).to start_with("PAY-")
      end

      # Note: Order status is updated by Order::ConfirmService in the workflow
      # The charge service only completes the payment

      it "returns paypal capture id" do
        expect(result.resource.transaction_id).to start_with("PAY-")
      end
    end

    context "with wrong provider" do
      let(:stripe_payment) do
        Payment.create!(
          order: confirmed_order,
          amount: confirmed_order.total,
          provider: :stripe,
          status: :processing
        )
      end
      let(:service) do
        described_class.new(user, params: { payment_id: stripe_payment.id })
      end

      it "returns a failure result for wrong provider" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:execution_error)
      end
    end
  end
end
