# frozen_string_literal: true

require "spec_helper"

RSpec.describe Payment::ProcessService do
  include_context "with payment"

  describe "#call" do
    context "processing pending payment as owner" do
      let(:service) { described_class.new(user, params: { payment_id: pending_payment.id }) }
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "changes payment status to processing" do
        result
        pending_payment.reload
        expect(pending_payment.status).to eq("processing")
      end

      it "includes processed action in metadata" do
        expect(result.meta[:action]).to eq(:processed)
      end
    end

    context "processing as admin" do
      let(:service) { described_class.new(admin_user, params: { payment_id: pending_payment.id }) }
      let(:result) { service.call }

      it "allows admin to process" do
        expect(result.success?).to be true
        pending_payment.reload
        expect(pending_payment.status).to eq("processing")
      end
    end

    context "processing already processing payment" do
      let(:service) { described_class.new(user, params: { payment_id: processing_payment.id }) }

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:execution_error)
      end
    end

    context "processing completed payment" do
      let(:service) { described_class.new(user, params: { payment_id: completed_payment.id }) }

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:execution_error)
      end
    end

    context "as non-owner" do
      let(:other_user) { User.create!(name: "Other", email: "other@example.com") }
      let(:service) { described_class.new(other_user, params: { payment_id: pending_payment.id }) }

      it_behaves_like "a service with authorization error"
    end

    context "with non-existent payment" do
      let(:service) { described_class.new(admin_user, params: { payment_id: 999999 }) }

      it_behaves_like "a service with resource not found error"
    end

    context "with invalid params" do
      it "raises validation error for missing payment_id" do
        expect {
          described_class.new(user, params: {})
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end
  end
end
