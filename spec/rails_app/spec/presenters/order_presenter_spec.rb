# frozen_string_literal: true

require "spec_helper"

RSpec.describe OrderPresenter do
  include_context "with order"

  let(:presenter) { described_class.new(order, current_user: user) }

  describe "#as_json" do
    subject(:json) { presenter.as_json }

    it "includes basic attributes" do
      expect(json[:id]).to eq(order.id)
      expect(json[:total]).to eq(order.total)
      expect(json[:status]).to eq(order.status)
      expect(json[:payment_method]).to eq(order.payment_method)
    end

    it "includes formatted total" do
      expect(json[:formatted_total]).to eq("$#{order.total}")
    end

    it "includes item count" do
      expect(json[:items_count]).to eq(order.order_items.count)
    end
  end

  describe "with include_items option" do
    let(:presenter) { described_class.new(order, current_user: user, fields: [ :items ]) }

    it "includes order items" do
      json = presenter.as_json
      expect(json[:items]).to be_present
      expect(json[:items].first[:product_id]).to eq(product.id)
    end
  end

  describe "with include_payment option" do
    let(:presenter) { described_class.new(paid_order, current_user: user, fields: [ :payment ]) }

    it "includes payment information" do
      json = presenter.as_json
      expect(json[:payment]).to be_present
      expect(json[:payment][:status]).to eq("completed")
    end
  end

  describe "as admin user" do
    let(:presenter) { described_class.new(order, current_user: admin_user) }

    it "includes customer information" do
      json = presenter.as_json
      expect(json[:customer]).to be_present
      expect(json[:customer][:id]).to eq(order.user.id)
    end
  end
end
