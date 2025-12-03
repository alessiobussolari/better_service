# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Order::ShowService do
  include_context "with order"

  describe "#call" do
    context "as order owner" do
      let(:service) { described_class.new(user, params: { id: order.id }) }
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "returns the order presenter" do
        expect(result.resource).to be_a(OrderPresenter)
        expect(result.resource.object).to eq(order)
      end

      it "includes showed action in metadata" do
        expect(result.meta[:action]).to eq(:showed)
      end
    end

    context "as admin" do
      let(:service) { described_class.new(admin_user, params: { id: order.id }) }
      let(:result) { service.call }

      it "allows admin to view any order" do
        expect(result.success?).to be true
        expect(result.resource).to be_a(OrderPresenter)
        expect(result.resource.object).to eq(order)
      end
    end

    context "as non-owner" do
      let(:other_user) { User.create!(name: "Other", email: "other@example.com") }
      let(:service) { described_class.new(other_user, params: { id: order.id }) }

      it_behaves_like "a service with authorization error"
    end

    context "with non-existent order" do
      let(:service) { described_class.new(admin_user, params: { id: 999999 }) }

      it_behaves_like "a service with resource not found error"
    end
  end
end
