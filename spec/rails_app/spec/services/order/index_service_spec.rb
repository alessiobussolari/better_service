# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Order::IndexService do
  include_context "with order"

  describe "#call" do
    context "listing user orders" do
      let(:service) { described_class.new(user, params: {}) }
      let(:result) { service.call }

      before { order } # create order

      it_behaves_like "a successful service"

      it "returns user's orders" do
        expect(result.resource.map(&:object)).to include(order)
      end

      it "returns order presenters" do
        expect(result.resource.first).to be_a(OrderPresenter)
      end

      it "includes listed action in metadata" do
        expect(result.meta[:action]).to eq(:listed)
      end

      it "includes count in metadata" do
        expect(result.meta[:count]).to eq(1)
      end
    end

    context "filtering by status" do
      before do
        order # pending
        confirmed_order # confirmed
      end

      it "filters pending orders" do
        result = described_class.new(user, params: { status: "pending" }).call
        statuses = result.resource.map { |o| o.object.status }
        expect(statuses).to all(eq("pending"))
      end

      it "filters confirmed orders" do
        result = described_class.new(user, params: { status: "confirmed" }).call
        statuses = result.resource.map { |o| o.object.status }
        expect(statuses).to all(eq("confirmed"))
      end
    end

    context "with pagination params" do
      let(:service) { described_class.new(user, params: { page: 1, per_page: 10 }) }
      let(:result) { service.call }

      it "returns paginated results" do
        order
        expect(result.success?).to be true
      end
    end

    context "excludes other users orders" do
      let(:other_user) { User.create!(name: "Other", email: "other@example.com") }
      let(:other_order) do
        Order.create!(user: other_user, total: 50.00, status: :pending, payment_method: :credit_card)
      end

      it "does not return other users orders" do
        order
        other_order
        result = described_class.new(user, params: {}).call
        order_ids = result.resource.map { |o| o.object.id }
        expect(order_ids).not_to include(other_order.id)
      end
    end

    context "with invalid params" do
      it "raises validation error for invalid status" do
        expect {
          described_class.new(user, params: { status: "invalid_status" })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end

      it "raises validation error for invalid page" do
        expect {
          described_class.new(user, params: { page: 0 })
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end
  end
end
