# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Repository Integration", type: :integration do
  let(:user) { User.create!(name: "Test User", email: "test@example.com") }
  let(:user2) { User.create!(name: "Other User", email: "other@example.com") }

  let!(:product1) { Product.create!(name: "Product 1", price: 10.00, published: true, user: user) }
  let!(:product2) { Product.create!(name: "Product 2", price: 20.00, published: false, user: user) }
  let!(:product3) { Product.create!(name: "Product 3", price: 30.00, published: true, user: user2) }

  let!(:booking1) { Booking.create!(title: "Past Booking", date: Date.current - 7.days, user: user) }
  let!(:booking2) { Booking.create!(title: "Today Booking", date: Date.current, user: user) }
  let!(:booking3) { Booking.create!(title: "Future Booking", date: Date.current + 7.days, user: user2) }

  let(:product_repo) { ProductRepository.new }
  let(:user_repo) { UserRepository.new }
  let(:booking_repo) { BookingRepository.new }

  # Clean all related tables before AND after each example to ensure isolation
  around do |example|
    Booking.delete_all
    Product.delete_all
    User.delete_all
    example.run
    Booking.delete_all
    Product.delete_all
    User.delete_all
  end

  describe "BaseRepository with Real Models" do
    describe "#find" do
      it "retrieves existing record" do
        result = product_repo.find(product1.id)

        expect(result.id).to eq product1.id
        expect(result.name).to eq "Product 1"
      end

      it "raises RecordNotFound for missing id" do
        expect { product_repo.find(999_999) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe "#find_by" do
      it "returns matching record" do
        result = product_repo.find_by(name: "Product 2")

        expect(result).not_to be_nil
        expect(result.id).to eq product2.id
      end

      it "returns nil when no match" do
        result = product_repo.find_by(name: "Non-existent")

        expect(result).to be_nil
      end
    end

    describe "#where" do
      it "returns filtered results" do
        results = product_repo.where(published: true).to_a

        expect(results.size).to eq 2
        expect(results.all?(&:published)).to be true
      end
    end

    describe "#all" do
      it "returns all records" do
        results = product_repo.all.to_a

        expect(results.size).to eq 3
      end
    end

    describe "#count" do
      it "returns correct count" do
        expect(product_repo.count).to eq 3
        expect(user_repo.count).to eq 2
        expect(booking_repo.count).to eq 3
      end
    end

    describe "#exists?" do
      it "returns true for matching condition" do
        expect(product_repo.exists?(name: "Product 1")).to be true
        expect(product_repo.exists?(name: "Non-existent")).to be false
      end
    end
  end

  describe "CRUD Operations" do
    describe "#build" do
      it "creates unsaved instance" do
        product = product_repo.build(name: "New Product", price: 15.00, user: user)

        expect(product).to be_a Product
        expect(product.name).to eq "New Product"
        expect(product).not_to be_persisted
      end
    end

    describe "#create" do
      it "persists new record to database" do
        initial_count = Product.count

        product = product_repo.create(name: "Created Product", price: 25.00, user: user)

        expect(product).to be_a Product
        expect(product).to be_persisted
        expect(Product.count).to eq initial_count + 1
      end
    end

    describe "#create!" do
      it "raises on validation failure" do
        expect {
          product_repo.create!(name: nil, price: 10.00, user: user)
        }.to raise_error(ActiveRecord::RecordInvalid)
      end

      it "succeeds with valid attributes" do
        product = product_repo.create!(name: "Valid Product", price: 50.00, user: user)

        expect(product).to be_a Product
        expect(product).to be_persisted
      end
    end

    describe "#update" do
      it "modifies existing record by instance" do
        product_repo.update(product1, name: "Updated Name")

        product1.reload
        expect(product1.name).to eq "Updated Name"
      end

      it "modifies existing record by id" do
        product_repo.update(product1.id, name: "Updated By ID")

        product1.reload
        expect(product1.name).to eq "Updated By ID"
      end
    end

    describe "#destroy" do
      it "removes record from database" do
        initial_count = Product.count

        product_repo.destroy(product1)

        expect(Product.count).to eq initial_count - 1
        expect(Product.exists?(product1.id)).to be false
      end

      it "removes record by id" do
        initial_count = Product.count

        product_repo.destroy(product2.id)

        expect(Product.count).to eq initial_count - 1
        expect(Product.exists?(product2.id)).to be false
      end
    end

    describe "#delete" do
      it "removes record without callbacks" do
        initial_count = Product.count

        product_repo.delete(product1.id)

        expect(Product.count).to eq initial_count - 1
      end
    end
  end

  describe "Search with Pagination" do
    it "returns all records with empty predicates" do
      results = product_repo.search({})

      expect(results).to respond_to(:to_a)
      expect(results.to_a.size).to eq 3
    end

    it "returns correct page with pagination" do
      results = product_repo.search({}, page: 1, per_page: 2)

      expect(results.to_a.size).to eq 2
    end

    it "returns remaining records on page 2" do
      results = product_repo.search({}, page: 2, per_page: 2)

      expect(results.to_a.size).to eq 1
    end

    it "returns limited results with limit" do
      results = product_repo.search({}, limit: 2)

      expect(results.to_a.size).to eq 2
    end

    it "returns single record with limit 1" do
      result = product_repo.search({}, limit: 1)

      expect(result).to be_a Product
    end

    it "returns all without pagination with limit nil" do
      results = product_repo.search({}, limit: nil)

      expect(results.to_a.size).to eq 3
    end

    it "eager loads associations with includes" do
      results = user_repo.search({}, includes: [ :products ])

      expect(results).to respond_to(:to_a)
      expect(results.first.products).not_to be_empty
    end

    it "sorts results with order DESC" do
      results = product_repo.search({}, order: "price DESC")

      prices = results.to_a.map(&:price)
      expect(prices).to eq prices.sort.reverse
    end

    it "sorts results with order ASC" do
      results = product_repo.search({}, order: "price ASC")

      prices = results.to_a.map(&:price)
      expect(prices).to eq prices.sort
    end
  end

  describe "Custom Repository Methods" do
    describe "ProductRepository" do
      it "#published returns only published products" do
        results = product_repo.published

        expect(results.count).to eq 2
        expect(results.all?(&:published)).to be true
      end

      it "#unpublished returns only unpublished products" do
        results = product_repo.unpublished

        expect(results.count).to eq 1
        expect(results.none?(&:published)).to be true
      end

      it "#by_user filters by user_id" do
        results = product_repo.by_user(user.id)

        expect(results.count).to eq 2
        expect(results.all? { |p| p.user_id == user.id }).to be true
      end

      it "#in_price_range filters by price range" do
        results = product_repo.in_price_range(15.00, 25.00)

        expect(results.count).to eq 1
        expect(results.first.id).to eq product2.id
      end
    end

    describe "UserRepository" do
      it "#with_products eager loads products" do
        results = user_repo.with_products

        found_user = results.find(user.id)
        expect(found_user.products).to be_loaded
      end

      it "#with_bookings eager loads bookings" do
        results = user_repo.with_bookings

        found_user = results.find(user.id)
        expect(found_user.bookings).to be_loaded
      end

      it "#with_all_associations eager loads all" do
        results = user_repo.with_all_associations

        found_user = results.find(user.id)
        expect(found_user.products).to be_loaded
        expect(found_user.bookings).to be_loaded
      end

      it "#find_by_email finds user" do
        result = user_repo.find_by_email("test@example.com")

        expect(result.id).to eq user.id
      end
    end

    describe "BookingRepository" do
      it "#upcoming returns future bookings" do
        results = booking_repo.upcoming

        expect(results.count).to eq 2
        expect(results.all? { |b| b.date >= Date.current }).to be true
      end

      it "#past returns past bookings" do
        results = booking_repo.past

        expect(results.count).to eq 1
        expect(results.all? { |b| b.date < Date.current }).to be true
      end

      it "#by_user filters by user_id" do
        results = booking_repo.by_user(user.id)

        expect(results.count).to eq 2
        expect(results.all? { |b| b.user_id == user.id }).to be true
      end

      it "#for_date finds bookings on specific date" do
        results = booking_repo.for_date(Date.current)

        expect(results.count).to eq 1
        expect(results.first.id).to eq booking2.id
      end
    end
  end

  describe "RepositoryAware Integration" do
    it "creates record via repository in service" do
      service_class = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::RepositoryAware
        repository :product, class_name: "ProductRepository"

        performed_action :created
        with_transaction true

        schema do
          required(:name).filled(:string)
          required(:price).filled(:decimal)
          required(:user_id).filled(:integer)
        end

        search_with { {} }

        process_with do |_data|
          { object: product_repository.create!(
            name: params[:name],
            price: params[:price],
            user_id: params[:user_id]
          ) }
        end

        respond_with do |data|
          { object: data[:object], success: true }
        end
      end

      service = service_class.new(user, params: { name: "Service Created", price: 99.99, user_id: user.id })
      product, meta = service.call

      expect(meta[:success]).to be true
      expect(product).to be_a Product
      expect(product.name).to eq "Service Created"
      expect(product).to be_persisted
    end

    it "performs search via repository" do
      service_class = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::RepositoryAware
        repository :product, class_name: "ProductRepository"

        performed_action :listed

        search_with do
          { items: product_repository.published.to_a }
        end

        respond_with do |data|
          { object: data[:items], success: true }
        end
      end

      service = service_class.new(user)
      items, meta = service.call

      expect(meta[:success]).to be true
      expect(items.size).to eq 2
      expect(items.all?(&:published)).to be true
    end

    it "works with multiple repositories" do
      service_class = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::RepositoryAware
        repository :product, class_name: "ProductRepository"
        repository :booking, class_name: "BookingRepository"

        performed_action :listed

        search_with do
          {
            items: product_repository.all.to_a,
            bookings: booking_repository.upcoming.to_a
          }
        end

        process_with do |data|
          {
            items: data[:items],
            bookings: data[:bookings],
            metadata: {
              product_count: data[:items].size,
              booking_count: data[:bookings].size
            }
          }
        end

        respond_with do |data|
          { object: data[:items], bookings: data[:bookings], metadata: data[:metadata], success: true }
        end
      end

      service = service_class.new(user)
      _items, meta = service.call

      expect(meta[:success]).to be true
      expect(meta[:product_count]).to eq 3
      expect(meta[:booking_count]).to eq 2
    end

    it "memoizes repository within service" do
      service_class = Class.new(BetterService::Services::Base) do
        include BetterService::Concerns::Serviceable::RepositoryAware
        repository :product, class_name: "ProductRepository"

        def repository_instances
          [ product_repository, product_repository, product_repository ]
        end
      end

      service = service_class.new(user)
      repos = service.repository_instances

      expect(repos[0]).to be repos[1]
      expect(repos[1]).to be repos[2]
    end
  end
end
