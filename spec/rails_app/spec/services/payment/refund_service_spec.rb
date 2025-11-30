# frozen_string_literal: true

require "spec_helper"

RSpec.describe Payment::RefundService do
  include_context "with payment"

  describe "#call" do
    context "refunding completed stripe payment" do
      let(:service) do
        described_class.new(admin_user, params: {
          payment_id: completed_payment.id,
          reason: "Customer request"
        })
      end
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "refunds the payment" do
        result
        completed_payment.reload
        expect(completed_payment.status).to eq("refunded")
      end

      it "sets refund_id with re_ prefix for stripe" do
        result
        completed_payment.reload
        expect(completed_payment.refund_id).to start_with("re_")
      end

      it "sets refunded_at" do
        result
        completed_payment.reload
        expect(completed_payment.refunded_at).to be_present
      end

      it "cancels the order" do
        result
        paid_order.reload
        expect(paid_order.status).to eq("cancelled")
      end

      it "returns refund id" do
        expect(result.resource.refund_id).to start_with("re_")
      end
    end

    context "refunding completed paypal payment" do
      let(:paypal_completed) do
        Payment.create!(
          order: confirmed_order,
          amount: confirmed_order.total,
          provider: :paypal,
          status: :completed,
          transaction_id: "PAY-123",
          completed_at: Time.current
        )
      end
      let(:service) do
        described_class.new(admin_user, params: { payment_id: paypal_completed.id })
      end

      it "sets refund_id with REF- prefix for paypal" do
        result = service.call
        paypal_completed.reload
        expect(paypal_completed.refund_id).to start_with("REF-")
      end
    end

    context "refunding pending payment" do
      let(:service) do
        described_class.new(admin_user, params: { payment_id: pending_payment.id })
      end

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:execution_error)
      end
    end

    context "as non-admin" do
      let(:service) do
        described_class.new(user, params: { payment_id: completed_payment.id })
      end

      it_behaves_like "a service with authorization error"
    end
  end
end
