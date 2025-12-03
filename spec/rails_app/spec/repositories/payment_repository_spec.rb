# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe PaymentRepository do
  include_context "with payment"

  let(:repository) { described_class.new }

  describe "#find" do
    it "finds payment by id" do
      found = repository.find(pending_payment.id)
      expect(found).to eq(pending_payment)
    end
  end

  describe "#by_order" do
    it "returns payments for specified order" do
      pending_payment # ensure payment exists
      payments = repository.by_order(order)
      expect(payments.first).to eq(pending_payment)
    end
  end

  describe "#by_status" do
    it "returns payments with specified status" do
      payments = repository.by_status(:pending)
      expect(payments).to include(pending_payment)
    end
  end

  describe "#by_provider" do
    it "returns payments for specified provider" do
      payments = repository.by_provider(:stripe)
      expect(payments).to include(pending_payment)
    end
  end

  describe "#with_order" do
    it "eager loads order association" do
      result = repository.with_order.find(pending_payment.id)
      expect(result.association(:order)).to be_loaded
    end
  end

  describe "#successful" do
    it "returns only completed payments" do
      payments = repository.successful
      expect(payments).to include(completed_payment)
      expect(payments).not_to include(pending_payment)
    end
  end

  describe "#create!" do
    it "creates a new payment" do
      new_payment = repository.create!(
        order: confirmed_order,
        amount: confirmed_order.total,
        provider: :paypal,
        status: :pending
      )

      expect(new_payment).to be_persisted
      expect(new_payment.provider).to eq("paypal")
    end
  end

  describe "#update!" do
    it "updates payment attributes" do
      repository.update!(pending_payment,
        status: :processing
      )
      pending_payment.reload
      expect(pending_payment.status).to eq("processing")
    end

    it "updates transaction_id" do
      repository.update!(pending_payment,
        transaction_id: "ch_test123"
      )
      pending_payment.reload
      expect(pending_payment.transaction_id).to eq("ch_test123")
    end
  end
end
