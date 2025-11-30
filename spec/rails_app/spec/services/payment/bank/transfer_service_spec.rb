# frozen_string_literal: true

require "spec_helper"

RSpec.describe Payment::Bank::TransferService do
  include_context "with order"

  let(:bank_payment) do
    Payment.create!(
      order: order,
      amount: order.total,
      provider: :bank,
      status: :processing
    )
  end

  describe "#call" do
    context "confirming bank transfer as admin" do
      let(:service) do
        described_class.new(admin_user, params: {
          payment_id: bank_payment.id,
          reference_number: "REF-2024-001"
        })
      end
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "completes the payment" do
        result
        bank_payment.reload
        expect(bank_payment.status).to eq("completed")
      end

      it "uses provided reference number" do
        result
        bank_payment.reload
        expect(bank_payment.transaction_id).to eq("REF-2024-001")
      end

      # Note: Order status is updated by Order::ConfirmService in the workflow
      # The transfer service only completes the payment
    end

    context "without reference number" do
      let(:service) do
        described_class.new(admin_user, params: { payment_id: bank_payment.id })
      end
      let(:result) { service.call }

      it "generates reference number" do
        result
        bank_payment.reload
        expect(bank_payment.transaction_id).to start_with("BT-")
      end
    end

    context "as non-admin" do
      let(:service) do
        described_class.new(user, params: { payment_id: bank_payment.id })
      end

      it_behaves_like "a service with authorization error"
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
        described_class.new(admin_user, params: { payment_id: stripe_payment.id })
      end

      it "returns a failure result for wrong provider" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:execution_error)
      end
    end
  end
end
