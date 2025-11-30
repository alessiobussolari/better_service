# frozen_string_literal: true

require "spec_helper"

RSpec.describe Product::UpdateService do
  include_context "with products"

  describe "#call" do
    context "as owner" do
      let(:service) do
        described_class.new(seller_user, params: {
          id: product.id,
          name: "Updated Name",
          price: 199.99
        })
      end
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "updates the product" do
        result
        product.reload
        expect(product.name).to eq("Updated Name")
        expect(product.price).to eq(199.99)
      end

      it "includes updated action in metadata" do
        expect(result.meta[:action]).to eq(:updated)
      end
    end

    context "as admin" do
      let(:service) do
        described_class.new(admin_user, params: {
          id: product.id,
          name: "Admin Updated"
        })
      end
      let(:result) { service.call }

      it "allows admin to update" do
        expect(result.success?).to be true
        product.reload
        expect(product.name).to eq("Admin Updated")
      end
    end

    context "as non-owner" do
      let(:other_user) { User.create!(name: "Other", email: "other@example.com") }
      let(:service) do
        described_class.new(other_user, params: { id: product.id, name: "Hacked" })
      end

      it_behaves_like "a service with authorization error"
    end

    context "with non-existent product" do
      let(:service) do
        described_class.new(admin_user, params: { id: 999999, name: "Test" })
      end

      it_behaves_like "a service with resource not found error"
    end
  end
end
