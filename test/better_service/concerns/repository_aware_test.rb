# frozen_string_literal: true

require "test_helper"

module BetterService
  module Concerns
    class RepositoryAwareTest < ActiveSupport::TestCase
      # ========================================
      # Mock Classes
      # ========================================

      # Simple mock model
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

      # Mock repositories
      class MockProductRepository < Repository::BaseRepository
        def initialize
          super(MockProduct)
        end

        def search(predicates = {}, **options)
          [MockProduct.new(id: 1, name: "Test Product")]
        end

        def create!(attrs)
          MockProduct.new(attrs.merge(id: 1))
        end
      end

      class MockUserRepository < Repository::BaseRepository
        def initialize
          super(MockUser)
        end

        def search(predicates = {}, **options)
          [MockUser.new(id: 1, email: "test@example.com")]
        end
      end

      class MockOrderRepository < Repository::BaseRepository
        def initialize
          super(MockOrder)
        end
      end

      # Namespaced repository
      module Custom
        class SpecialRepository < Repository::BaseRepository
          def initialize
            super(MockProduct)
          end

          def special_method
            "special"
          end
        end
      end

      # Dummy user for services
      class DummyUser
        attr_accessor :id

        def initialize(id: 1)
          @id = id
        end
      end

      # ========================================
      # Test Group 1: Repository DSL
      # ========================================

      test "repository creates accessor method" do
        service_class = Class.new(Services::Base) do
          include Serviceable::RepositoryAware
          repository :mock_product
        end

        service = service_class.new(DummyUser.new)

        assert service.respond_to?(:mock_product_repository, true)
      end

      test "repository accessor is private" do
        service_class = Class.new(Services::Base) do
          include Serviceable::RepositoryAware
          repository :mock_product
        end

        service = service_class.new(DummyUser.new)

        refute service.respond_to?(:mock_product_repository)
        assert service.respond_to?(:mock_product_repository, true)
      end

      test "repository derives class name from name" do
        # MockProductRepository should be derived from :mock_product with class_name
        service_class = Class.new(Services::Base) do
          include Serviceable::RepositoryAware
          repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareTest::MockProductRepository"
        end

        service = service_class.new(DummyUser.new)
        repo = service.send(:mock_product_repository)

        assert_kind_of MockProductRepository, repo
      end

      test "repository uses explicit class_name" do
        service_class = Class.new(Services::Base) do
          include Serviceable::RepositoryAware
          repository :product, class_name: "BetterService::Concerns::RepositoryAwareTest::Custom::SpecialRepository"
        end

        service = service_class.new(DummyUser.new)
        repo = service.send(:product_repository)

        assert_kind_of Custom::SpecialRepository, repo
        assert_equal "special", repo.special_method
      end

      test "repository uses custom accessor with as option" do
        service_class = Class.new(Services::Base) do
          include Serviceable::RepositoryAware
          repository :mock_product, as: :products, class_name: "BetterService::Concerns::RepositoryAwareTest::MockProductRepository"
        end

        service = service_class.new(DummyUser.new)

        assert service.respond_to?(:products, true)
        refute service.respond_to?(:mock_product_repository, true)

        repo = service.send(:products)
        assert_kind_of MockProductRepository, repo
      end

      # ========================================
      # Test Group 2: Memoization
      # ========================================

      test "repository accessor is memoized" do
        service_class = Class.new(Services::Base) do
          include Serviceable::RepositoryAware
          repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareTest::MockProductRepository"
        end

        service = service_class.new(DummyUser.new)

        repo1 = service.send(:mock_product_repository)
        repo2 = service.send(:mock_product_repository)

        assert_same repo1, repo2
      end

      test "repository returns same instance on multiple calls" do
        service_class = Class.new(Services::Base) do
          include Serviceable::RepositoryAware
          repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareTest::MockProductRepository"
        end

        service = service_class.new(DummyUser.new)

        # Call multiple times
        repos = 5.times.map { service.send(:mock_product_repository) }

        # All should be the exact same object
        repos.each { |r| assert_same repos.first, r }
      end

      test "different service instances have different repository instances" do
        service_class = Class.new(Services::Base) do
          include Serviceable::RepositoryAware
          repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareTest::MockProductRepository"
        end

        service1 = service_class.new(DummyUser.new)
        service2 = service_class.new(DummyUser.new)

        repo1 = service1.send(:mock_product_repository)
        repo2 = service2.send(:mock_product_repository)

        refute_same repo1, repo2
      end

      # ========================================
      # Test Group 3: Multiple Repositories
      # ========================================

      test "repositories shorthand creates multiple accessors" do
        service_class = Class.new(Services::Base) do
          include Serviceable::RepositoryAware
          repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareTest::MockProductRepository"
          repository :mock_user, class_name: "BetterService::Concerns::RepositoryAwareTest::MockUserRepository"
          repository :mock_order, class_name: "BetterService::Concerns::RepositoryAwareTest::MockOrderRepository"
        end

        service = service_class.new(DummyUser.new)

        assert service.respond_to?(:mock_product_repository, true)
        assert service.respond_to?(:mock_user_repository, true)
        assert service.respond_to?(:mock_order_repository, true)
      end

      test "multiple repository declarations work independently" do
        service_class = Class.new(Services::Base) do
          include Serviceable::RepositoryAware
          repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareTest::MockProductRepository"
          repository :mock_user, class_name: "BetterService::Concerns::RepositoryAwareTest::MockUserRepository"
        end

        service = service_class.new(DummyUser.new)

        product_repo = service.send(:mock_product_repository)
        user_repo = service.send(:mock_user_repository)

        assert_kind_of MockProductRepository, product_repo
        assert_kind_of MockUserRepository, user_repo
        refute_same product_repo, user_repo
      end

      test "each repository is independently memoized" do
        service_class = Class.new(Services::Base) do
          include Serviceable::RepositoryAware
          repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareTest::MockProductRepository"
          repository :mock_user, class_name: "BetterService::Concerns::RepositoryAwareTest::MockUserRepository"
        end

        service = service_class.new(DummyUser.new)

        product_repo1 = service.send(:mock_product_repository)
        user_repo1 = service.send(:mock_user_repository)
        product_repo2 = service.send(:mock_product_repository)
        user_repo2 = service.send(:mock_user_repository)

        assert_same product_repo1, product_repo2
        assert_same user_repo1, user_repo2
      end

      # ========================================
      # Test Group 4: Integration with Services
      # ========================================

      test "repository can be used in service search_with block" do
        service_class = Class.new(Services::IndexService) do
          include Serviceable::RepositoryAware
          repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareTest::MockProductRepository"

          search_with do
            { items: mock_product_repository.search({}) }
          end
        end

        service = service_class.new(DummyUser.new)
        result = service.call

        assert result[:success]
        assert_equal 1, result[:items].length
        assert_equal "Test Product", result[:items].first.name
      end

      test "repository can be used in service process_with block" do
        service_class = Class.new(Services::CreateService) do
          include Serviceable::RepositoryAware
          repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareTest::MockProductRepository"

          schema do
            required(:name).filled(:string)
          end

          search_with do
            {}
          end

          process_with do |_data|
            { resource: mock_product_repository.create!(name: params[:name]) }
          end
        end

        service = service_class.new(DummyUser.new, params: { name: "New Product" })
        result = service.call

        assert result[:success]
        assert_equal "New Product", result[:resource].name
      end

      test "multiple repositories can be used in same service" do
        service_class = Class.new(Services::IndexService) do
          include Serviceable::RepositoryAware
          repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareTest::MockProductRepository"
          repository :mock_user, class_name: "BetterService::Concerns::RepositoryAwareTest::MockUserRepository"

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
        end

        service = service_class.new(DummyUser.new)
        result = service.call

        assert result[:success]
        assert_equal 1, result[:items].length
        assert_equal 1, result[:metadata][:product_count]
        assert_equal 1, result[:metadata][:user_count]
      end

      # ========================================
      # Test Group 5: Edge Cases
      # ========================================

      test "repository raises NameError for non-existent class" do
        service_class = Class.new(Services::Base) do
          include Serviceable::RepositoryAware
          repository :non_existent
        end

        service = service_class.new(DummyUser.new)

        assert_raises(NameError) do
          service.send(:non_existent_repository)
        end
      end

      test "repository with class_name raises NameError for invalid class" do
        service_class = Class.new(Services::Base) do
          include Serviceable::RepositoryAware
          repository :product, class_name: "InvalidClass::ThatDoesNotExist"
        end

        service = service_class.new(DummyUser.new)

        assert_raises(NameError) do
          service.send(:product_repository)
        end
      end

      test "repository accessor can be called before any other method" do
        service_class = Class.new(Services::Base) do
          include Serviceable::RepositoryAware
          repository :mock_product, class_name: "BetterService::Concerns::RepositoryAwareTest::MockProductRepository"
        end

        service = service_class.new(DummyUser.new)

        # Should work even before call
        repo = service.send(:mock_product_repository)
        assert_kind_of MockProductRepository, repo
      end
    end
  end
end
