# frozen_string_literal: true

require "spec_helper"

RSpec.describe Product::PublishService do
  include_context "with products"

  describe "#call" do
    context "publishing unpublished product as owner" do
      let(:service) do
        described_class.new(seller_user, params: { id: unpublished_product.id })
      end
      let(:result) { service.call }

      it_behaves_like "a successful service"

      it "publishes the product" do
        result
        unpublished_product.reload
        expect(unpublished_product.published).to be true
      end

      it "includes published action in metadata" do
        expect(result.meta[:action]).to eq(:published)
      end
    end

    context "publishing already published product" do
      let(:service) do
        described_class.new(seller_user, params: { id: product.id })
      end

      it "returns a failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.meta[:error_code]).to eq(:execution_error)
      end
    end

    context "as admin" do
      let(:service) do
        described_class.new(admin_user, params: { id: unpublished_product.id })
      end

      it "allows admin to publish" do
        result = service.call
        expect(result.success?).to be true
      end
    end

    context "as non-owner" do
      let(:other_user) { User.create!(name: "Other", email: "other@example.com") }
      let(:service) do
        described_class.new(other_user, params: { id: unpublished_product.id })
      end

      it_behaves_like "a service with authorization error"
    end
  end
end
