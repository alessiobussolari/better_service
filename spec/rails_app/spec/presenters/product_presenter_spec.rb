# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe ProductPresenter do
  include_context "with products"

  let(:presenter) { described_class.new(product, current_user: user) }

  describe "#as_json" do
    subject(:json) { presenter.as_json }

    it "includes basic attributes" do
      expect(json[:id]).to eq(product.id)
      expect(json[:name]).to eq(product.name)
      expect(json[:price]).to eq(product.price)
      expect(json[:published]).to eq(product.published)
    end

    it "includes formatted price" do
      expect(json[:formatted_price]).to eq("$#{product.price}")
    end

    it "includes stock status" do
      expect(json[:in_stock]).to eq(product.in_stock?)
    end
  end

  describe "with include_owner option" do
    let(:presenter) { described_class.new(product, current_user: user, include_owner: true) }

    it "includes owner information" do
      json = presenter.as_json
      expect(json[:owner]).to be_present
      expect(json[:owner][:id]).to eq(product.user.id)
    end
  end

  describe "as admin user" do
    let(:presenter) { described_class.new(product, current_user: admin_user) }

    it "includes admin-only fields" do
      json = presenter.as_json
      expect(json).to have_key(:stock)
    end
  end

  describe "#to_json" do
    it "returns valid JSON string" do
      json_string = presenter.to_json
      expect { JSON.parse(json_string) }.not_to raise_error
    end
  end
end
