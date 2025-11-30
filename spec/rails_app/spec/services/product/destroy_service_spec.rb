# frozen_string_literal: true

require "spec_helper"

RSpec.describe Product::DestroyService do
  include_context "with products"

  describe "#call" do
    context "as owner" do
      let(:service) do
        described_class.new(seller_user, params: { id: product.id })
      end
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "destroys the product" do
        product # create
        expect { service.call }.to change(Product, :count).by(-1)
      end

      it "includes destroyed action in metadata" do
        expect(result.meta[:action]).to eq(:destroyed)
      end
    end

    context "as admin" do
      let(:service) do
        described_class.new(admin_user, params: { id: product.id })
      end

      it "allows admin to destroy" do
        product
        expect { service.call }.to change(Product, :count).by(-1)
      end
    end

    context "as non-owner" do
      let(:other_user) { User.create!(name: "Other", email: "other@example.com") }
      let(:service) do
        described_class.new(other_user, params: { id: product.id })
      end

      it_behaves_like "a service with authorization error"
    end

    context "with non-existent product" do
      let(:service) do
        described_class.new(admin_user, params: { id: 999999 })
      end

      it_behaves_like "a service with resource not found error"
    end
  end
end
