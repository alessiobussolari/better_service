# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Product Services Integration", type: :integration do
  let(:user) { User.create!(name: "Test User", email: "test@example.com", seller: true) }

  before do
    Rails.cache.clear
  end

  after do
    Product.destroy_all
    User.destroy_all
    Rails.cache.clear
  end

  describe "CreateService" do
    it "creates product with valid params" do
      product, meta = Product::CreateService.new(user, params: {
        name: "Test Product",
        price: 99.99
      }).call

      expect(meta[:success]).to be true
      expect(meta[:action]).to eq :created
      expect(product).to be_a Product
      expect(product.name).to eq "Test Product"
      expect(product.price.to_f).to eq 99.99
      expect(Product.count).to eq 1
    end

    it "raises ValidationError with invalid params" do
      expect {
        Product::CreateService.new(user, params: {
          name: "",
          price: -10
        })
      }.to raise_error(BetterService::Errors::Runtime::ValidationError) do |error|
        expect(error.code).to eq :validation_failed
        expect(error.context[:validation_errors]).to be_present
      end
    end

    it "handles transaction correctly" do
      initial_count = Product.count

      product, meta = Product::CreateService.new(user, params: {
        name: "Valid Name",
        price: 50
      }).call

      if meta[:success]
        expect(Product.count).to eq initial_count + 1
      else
        expect(Product.count).to eq initial_count
      end
    end
  end

  describe "IndexService" do
    before do
      Product.create!(name: "Product 1", price: 10, user: user)
      Product.create!(name: "Product 2", price: 20, user: user)
      Product.create!(name: "Product 3", price: 30, user: user)
    end

    it "returns list of products" do
      products, meta = Product::IndexService.new(user).call

      expect(meta[:success]).to be true
      expect(meta[:action]).to eq :listed
      expect(products.count).to eq 3
    end

    it "supports search functionality" do
      Product.create!(name: "Apple iPhone", price: 999, user: user)
      Product.create!(name: "Samsung Galaxy", price: 899, user: user)
      Product.create!(name: "Apple iPad", price: 599, user: user)

      products, meta = Product::IndexService.new(user, params: { search: "Apple" }).call

      expect(meta[:success]).to be true
      expect(products.count).to eq 2
      # Presenter wraps objects, so we need to access the underlying object or use presenter's delegated method
      expect(products.all? { |p| p.object.name.include?("Apple") }).to be true
    end
  end

  describe "ShowService" do
    it "returns single product" do
      product = Product.create!(name: "Test Product", price: 50, user: user)

      result_product, meta = Product::ShowService.new(user, params: { id: product.id }).call

      expect(meta[:success]).to be true
      expect(meta[:action]).to eq :showed
      # ShowService returns a ProductPresenter, so access the underlying object
      expect(result_product.object.id).to eq product.id
    end

    it "fails with invalid id" do
      product, meta = Product::ShowService.new(user, params: { id: 99999 }).call

      # Either returns error_code or success is false
      expect(meta[:success]).to be false
    end
  end

  describe "UpdateService" do
    it "updates product successfully" do
      product = Product.create!(name: "Old Name", price: 50, user: user)

      updated_product, meta = Product::UpdateService.new(user, params: {
        id: product.id,
        name: "New Name",
        price: 75
      }).call

      expect(meta[:success]).to be true
      expect(meta[:action]).to eq :updated
      product.reload
      expect(product.name).to eq "New Name"
      expect(product.price.to_f).to eq 75
    end

    it "fails with validation error for invalid params" do
      product = Product.create!(name: "Original", price: 50, user: user)

      # Schema validation happens during initialization
      expect {
        Product::UpdateService.new(user, params: {
          id: product.id,
          name: "",
          price: -10
        })
      }.to raise_error(BetterService::Errors::Runtime::ValidationError)

      product.reload
      expect(product.name).to eq "Original"
      expect(product.price.to_f).to eq 50
    end
  end

  describe "DestroyService" do
    it "deletes product successfully" do
      product = Product.create!(name: "To Delete", price: 50, user: user)
      initial_count = Product.count

      destroyed_product, meta = Product::DestroyService.new(user, params: { id: product.id }).call

      expect(meta[:success]).to be true
      expect(meta[:action]).to eq :destroyed
      expect(Product.count).to eq initial_count - 1
      expect { Product.find(product.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "PublishService (action)" do
    it "publishes product" do
      product = Product.create!(name: "Unpublished", price: 50, published: false, user: user)

      published_product, meta = Product::PublishService.new(user, params: { id: product.id }).call

      expect(meta[:success]).to be true
      expect(meta[:action]).to eq :published
      product.reload
      expect(product.published).to be true
    end
  end

  describe "Full workflow integration" do
    it "completes create, update, publish, destroy flow" do
      # Step 1: Create
      created_product, create_meta = Product::CreateService.new(user, params: {
        name: "Workflow Product",
        price: 100
      }).call
      expect(create_meta[:success]).to be true
      product_id = created_product.id

      # Step 2: Update
      updated_product, update_meta = Product::UpdateService.new(user, params: {
        id: product_id,
        price: 120
      }).call
      expect(update_meta[:success]).to be true
      expect(updated_product.price.to_f).to eq 120

      # Step 3: Publish
      _, publish_meta = Product::PublishService.new(user, params: { id: product_id }).call
      expect(publish_meta[:success]).to be true

      # Step 4: Verify with Show
      shown_product, show_meta = Product::ShowService.new(user, params: { id: product_id }).call
      expect(show_meta[:success]).to be true
      # ShowService returns a ProductPresenter, so access the underlying object
      expect(shown_product.object.published).to be true

      # Step 5: Destroy
      _, destroy_meta = Product::DestroyService.new(user, params: { id: product_id }).call
      expect(destroy_meta[:success]).to be true
      expect(Product.count).to eq 0
    end
  end

  describe "Authorization" do
    it "passes when authorized" do
      service_class = Class.new(BetterService::Services::Base) do
        performed_action :updated
        with_transaction true

        schema { required(:id).filled(:integer) }

        authorize_with { true }

        search_with { { object: Product.find(params[:id]) } }

        process_with do |data|
          data[:object].update!(name: "Authorized Update")
          { object: data[:object] }
        end

        respond_with do |data|
          { object: data[:object], message: "Updated successfully" }
        end
      end

      product = Product.create!(name: "Original", price: 50, user: user)
      updated_product, meta = service_class.new(user, params: { id: product.id }).call

      expect(meta[:success]).to be true
      expect(meta[:action]).to eq :updated
      expect(updated_product.name).to eq "Authorized Update"
    end

    it "fails when not authorized" do
      service_class = Class.new(BetterService::Services::Base) do
        performed_action :updated
        with_transaction true

        schema { required(:id).filled(:integer) }

        authorize_with { false }

        search_with { { object: Product.find(params[:id]) } }

        process_with do |data|
          data[:object].update!(name: "Should Not Update")
          { object: data[:object] }
        end
      end

      product = Product.create!(name: "Original", price: 50, user: user)

      _, meta = service_class.new(user, params: { id: product.id }).call

      expect(meta[:success]).to be false
      expect(meta[:error_code]).to eq :unauthorized

      product.reload
      expect(product.name).to eq "Original"
    end

    it "fails fast before search when authorization fails" do
      search_executed = false

      service_class = Class.new(BetterService::Services::Base) do
        performed_action :updated
        with_transaction true

        schema { required(:id).filled(:integer) }

        authorize_with { false }

        search_with do
          search_executed = true
          { object: Product.find(params[:id]) }
        end

        process_with { |data| { object: data[:object] } }

        define_method(:search_executed?) { search_executed }
      end

      product = Product.create!(name: "Test", price: 50, user: user)

      _, meta = service_class.new(user, params: { id: product.id }).call

      expect(meta[:success]).to be false
      expect(meta[:error_code]).to eq :unauthorized
      expect(search_executed).to be false
    end

    it "checks resource ownership" do
      other_user = User.create!(name: "Other User", email: "other@example.com")
      product = Product.create!(name: "Owner Product", price: 50, user: user)

      service_class = Class.new(BetterService::Services::Base) do
        performed_action :updated
        with_transaction true

        schema { required(:id).filled(:integer) }

        authorize_with do
          product = Product.find(params[:id])
          product.user_id == user.id
        end

        search_with { { object: Product.find(params[:id]) } }

        process_with do |data|
          data[:object].update!(name: "Updated by Owner")
          { object: data[:object] }
        end

        respond_with do |data|
          { object: data[:object], message: "Updated successfully" }
        end
      end

      # Owner should succeed
      updated_product, meta = service_class.new(user, params: { id: product.id }).call
      expect(meta[:success]).to be true

      # Other user should fail
      _, other_meta = service_class.new(other_user, params: { id: product.id }).call
      expect(other_meta[:success]).to be false
      expect(other_meta[:error_code]).to eq :unauthorized
    end
  end
end
