# frozen_string_literal: true

require "rails_helper"

module BetterService
  module Concerns
    RSpec.describe "RepositoryAware concern" do
      # Mock models
      let(:mock_product_class) do
        Class.new do
          attr_accessor :id, :name

          def initialize(attrs = {})
            attrs.each { |k, v| send("#{k}=", v) }
          end
        end
      end

      let(:mock_user_class) do
        Class.new do
          attr_accessor :id, :email

          def initialize(attrs = {})
            attrs.each { |k, v| send("#{k}=", v) }
          end
        end
      end

      let(:mock_order_class) do
        Class.new do
          attr_accessor :id, :total

          def initialize(attrs = {})
            attrs.each { |k, v| send("#{k}=", v) }
          end
        end
      end

      # Mock repositories - defined as constants for class_name lookup
      before(:all) do
        # Define repositories in BetterService::Concerns namespace
        module ::BetterService::Concerns::RepositoryAwareSpec
          class MockProduct
            attr_accessor :id, :name
            def initialize(attrs = {})
              attrs.each { |k, v| send("#{k}=", v) }
            end
          end

          class MockUser
            attr_accessor :id, :email
            def initialize(attrs = {})
              attrs.each { |k, v| send("#{k}=", v) }
            end
          end

          class MockOrder
            attr_accessor :id, :total
            def initialize(attrs = {})
              attrs.each { |k, v| send("#{k}=", v) }
            end
          end

          class MockProductRepository < BetterService::Repository::BaseRepository
            def initialize
              super(MockProduct)
            end

            def search(predicates = {}, **options)
              [ MockProduct.new(id: 1, name: "Test Product") ]
            end

            def create!(attrs)
              MockProduct.new(attrs.merge(id: 1))
            end
          end

          class MockUserRepository < BetterService::Repository::BaseRepository
            def initialize
              super(MockUser)
            end

            def search(predicates = {}, **options)
              [ MockUser.new(id: 1, email: "test@example.com") ]
            end
          end

          class MockOrderRepository < BetterService::Repository::BaseRepository
            def initialize
              super(MockOrder)
            end
          end

          module Custom
            class SpecialRepository < BetterService::Repository::BaseRepository
              def initialize
                super(MockProduct)
              end

              def special_method
                "special"
              end
            end
          end
        end
      end

      after(:all) do
        BetterService::Concerns.send(:remove_const, :RepositoryAwareSpec) if defined?(BetterService::Concerns::RepositoryAwareSpec)
      end

      let(:dummy_user_class) do
        Class.new do
          attr_accessor :id

          def initialize(id: 1)
            @id = id
          end
        end
      end

      let(:user) { dummy_user_class.new }

      describe "repository DSL" do
        it "creates accessor method" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :mock_product
          end

          service = service_class.new(user)
          expect(service.respond_to?(:mock_product_repository, true)).to be true
        end

        it "accessor is private" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :mock_product
          end

          service = service_class.new(user)
          expect(service.respond_to?(:mock_product_repository)).to be false
          expect(service.respond_to?(:mock_product_repository, true)).to be true
        end

        it "derives class name from name" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockProductRepository"
          end

          service = service_class.new(user)
          repo = service.send(:mock_product_repository)

          expect(repo).to be_a(BetterService::Concerns::RepositoryAwareSpec::MockProductRepository)
        end

        it "uses explicit class_name" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :product, class_name: "BetterService::Concerns::RepositoryAwareSpec::Custom::SpecialRepository"
          end

          service = service_class.new(user)
          repo = service.send(:product_repository)

          expect(repo).to be_a(BetterService::Concerns::RepositoryAwareSpec::Custom::SpecialRepository)
          expect(repo.special_method).to eq("special")
        end

        it "uses custom accessor with as option" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :mock_product, as: :products, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockProductRepository"
          end

          service = service_class.new(user)

          expect(service.respond_to?(:products, true)).to be true
          expect(service.respond_to?(:mock_product_repository, true)).to be false

          repo = service.send(:products)
          expect(repo).to be_a(BetterService::Concerns::RepositoryAwareSpec::MockProductRepository)
        end
      end

      describe "memoization" do
        it "accessor is memoized" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockProductRepository"
          end

          service = service_class.new(user)

          repo1 = service.send(:mock_product_repository)
          repo2 = service.send(:mock_product_repository)

          expect(repo1).to be(repo2)
        end

        it "returns same instance on multiple calls" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockProductRepository"
          end

          service = service_class.new(user)

          repos = 5.times.map { service.send(:mock_product_repository) }
          repos.each { |r| expect(r).to be(repos.first) }
        end

        it "different service instances have different repository instances" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockProductRepository"
          end

          service1 = service_class.new(user)
          service2 = service_class.new(user)

          repo1 = service1.send(:mock_product_repository)
          repo2 = service2.send(:mock_product_repository)

          expect(repo1).not_to be(repo2)
        end
      end

      describe "multiple repositories" do
        it "creates multiple accessors" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockProductRepository"
            repository :mock_user, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockUserRepository"
            repository :mock_order, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockOrderRepository"
          end

          service = service_class.new(user)

          expect(service.respond_to?(:mock_product_repository, true)).to be true
          expect(service.respond_to?(:mock_user_repository, true)).to be true
          expect(service.respond_to?(:mock_order_repository, true)).to be true
        end

        it "multiple repository declarations work independently" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockProductRepository"
            repository :mock_user, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockUserRepository"
          end

          service = service_class.new(user)

          product_repo = service.send(:mock_product_repository)
          user_repo = service.send(:mock_user_repository)

          expect(product_repo).to be_a(BetterService::Concerns::RepositoryAwareSpec::MockProductRepository)
          expect(user_repo).to be_a(BetterService::Concerns::RepositoryAwareSpec::MockUserRepository)
          expect(product_repo).not_to be(user_repo)
        end

        it "each repository is independently memoized" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockProductRepository"
            repository :mock_user, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockUserRepository"
          end

          service = service_class.new(user)

          product_repo1 = service.send(:mock_product_repository)
          user_repo1 = service.send(:mock_user_repository)
          product_repo2 = service.send(:mock_product_repository)
          user_repo2 = service.send(:mock_user_repository)

          expect(product_repo1).to be(product_repo2)
          expect(user_repo1).to be(user_repo2)
        end
      end

      describe "integration with services" do
        it "can be used in search_with block" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockProductRepository"

            performed_action :listed

            search_with do
              { items: mock_product_repository.search({}) }
            end

            respond_with do |data|
              { object: data[:items], success: true }
            end
          end

          service = service_class.new(user)
          items, meta = service.call

          expect(meta[:success]).to be true
          expect(items.length).to eq(1)
          expect(items.first.name).to eq("Test Product")
        end

        it "can be used in process_with block" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockProductRepository"

            performed_action :created
            with_transaction true

            schema do
              required(:name).filled(:string)
            end

            search_with do
              {}
            end

            process_with do |_data|
              { object: mock_product_repository.create!(name: params[:name]) }
            end

            respond_with do |data|
              { object: data[:object], success: true }
            end
          end

          service = service_class.new(user, params: { name: "New Product" })
          product, meta = service.call

          expect(meta[:success]).to be true
          expect(product.name).to eq("New Product")
        end

        it "multiple repositories can be used in same service" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockProductRepository"
            repository :mock_user, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockUserRepository"

            performed_action :listed

            search_with do
              {
                items: mock_product_repository.search({}),
                users: mock_user_repository.search({})
              }
            end

            process_with do |data|
              {
                items: data[:items],
                users: data[:users],
                metadata: {
                  product_count: data[:items].length,
                  user_count: data[:users].length
                }
              }
            end

            respond_with do |data|
              { object: data[:items], users: data[:users], metadata: data[:metadata], success: true }
            end
          end

          service = service_class.new(user)
          items, meta = service.call

          expect(meta[:success]).to be true
          expect(items.length).to eq(1)
          expect(meta[:product_count]).to eq(1)
          expect(meta[:user_count]).to eq(1)
        end
      end

      describe "edge cases" do
        it "raises NameError for non-existent class" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :non_existent
          end

          service = service_class.new(user)

          expect {
            service.send(:non_existent_repository)
          }.to raise_error(NameError)
        end

        it "raises NameError for invalid class_name" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :product, class_name: "InvalidClass::ThatDoesNotExist"
          end

          service = service_class.new(user)

          expect {
            service.send(:product_repository)
          }.to raise_error(NameError)
        end

        it "accessor can be called before call" do
          service_class = Class.new(Services::Base) do
            include Serviceable::RepositoryAware
            repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareSpec::MockProductRepository"
          end

          service = service_class.new(user)

          repo = service.send(:mock_product_repository)
          expect(repo).to be_a(BetterService::Concerns::RepositoryAwareSpec::MockProductRepository)
        end
      end
    end
  end
end
