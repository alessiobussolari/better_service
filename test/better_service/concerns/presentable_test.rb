# frozen_string_literal: true

require "test_helper"

module BetterService
  module Concerns
    class PresentableTest < ActiveSupport::TestCase
      # Dummy user class for testing
      class DummyUser
        attr_accessor :id, :name

        def initialize(id: 1, name: "Test User")
          @id = id
          @name = name
        end
      end

      # Dummy presenter for testing
      class DummyPresenter
        attr_reader :object, :options

        def initialize(object, **options)
          @object = object
          @options = options
        end

        def name
          object[:name]&.upcase || "N/A"
        end
      end

      # Service with presenter configured
      class ServiceWithPresenter < Base
        presenter DummyPresenter

        search_with do
          { items: [{ name: "Item 1" }, { name: "Item 2" }] }
        end
      end

      # Service with presenter options
      class ServiceWithPresenterOptions < Base
        presenter DummyPresenter
        presenter_options { { currency: "USD" } }
      end

      def setup
        @user = DummyUser.new
      end

      # ========================================
      # Test Group 1: Presenter Configuration
      # ========================================

      test "presenter DSL sets _presenter_class" do
        assert_equal DummyPresenter, ServiceWithPresenter._presenter_class
      end

      test "presenter configuration inherited by subclasses" do
        subclass = Class.new(ServiceWithPresenter)

        assert_equal DummyPresenter, subclass._presenter_class
      end

      test "_presenter_class defaults to nil" do
        assert_nil Base._presenter_class
      end

      test "presenter_options DSL stores options block" do
        assert_not_nil ServiceWithPresenterOptions._presenter_options

        service = ServiceWithPresenterOptions.new(@user)
        options = service.send(:instance_eval, &ServiceWithPresenterOptions._presenter_options)

        assert_equal "USD", options[:currency]
      end

      # ========================================
      # Test Group 2: Collection Presentation
      # ========================================

      test "transform applies presenter to items collection" do
        service = ServiceWithPresenter.new(@user)
        data = { items: [{ name: "Item 1" }, { name: "Item 2" }] }

        result = service.send(:transform, data)

        assert result[:items].all? { |item| item.is_a?(DummyPresenter) }
        assert_equal 2, result[:items].count
      end

      test "transform handles empty items array" do
        service = ServiceWithPresenter.new(@user)
        data = { items: [] }

        result = service.send(:transform, data)

        assert_equal [], result[:items]
      end

      test "presenter initialized with options for collection" do
        service = ServiceWithPresenterOptions.new(@user)
        data = { items: [{ price: 100 }] }

        result = service.send(:transform, data)
        presenter = result[:items].first

        assert_equal "USD", presenter.options[:currency]
      end

      test "transform preserves additional data with items" do
        service = ServiceWithPresenter.new(@user)
        data = { items: [{ name: "Item" }], pagination: { page: 1 }, stats: { total: 10 } }

        result = service.send(:transform, data)

        assert result[:items].all? { |i| i.is_a?(DummyPresenter) }
        assert_equal({ page: 1 }, result[:pagination])
        assert_equal({ total: 10 }, result[:stats])
      end

      test "transform handles nil items gracefully" do
        service = ServiceWithPresenter.new(@user)
        data = { items: [nil, { name: "Valid" }] }

        result = service.send(:transform, data)

        assert_equal 2, result[:items].count
        assert result[:items].all? { |i| i.is_a?(DummyPresenter) }
      end

      # ========================================
      # Test Group 3: Single Resource Presentation
      # ========================================

      test "transform applies presenter to single resource" do
        service = ServiceWithPresenter.new(@user)
        data = { resource: { name: "Resource 1" } }

        result = service.send(:transform, data)

        assert result[:resource].is_a?(DummyPresenter)
      end

      test "presenter initialized with options for resource" do
        service = ServiceWithPresenterOptions.new(@user)
        data = { resource: { price: 100 } }

        result = service.send(:transform, data)

        assert_equal "USD", result[:resource].options[:currency]
      end

      test "transform preserves additional data with resource" do
        service = ServiceWithPresenter.new(@user)
        data = { resource: { name: "Item" }, metadata: { version: 1 } }

        result = service.send(:transform, data)

        assert result[:resource].is_a?(DummyPresenter)
        assert_equal({ version: 1 }, result[:metadata])
      end

      test "transform handles nil resource" do
        service = ServiceWithPresenter.new(@user)
        data = { resource: nil }

        result = service.send(:transform, data)

        assert result[:resource].is_a?(DummyPresenter)
      end

      # ========================================
      # Test Group 4: Edge Cases & Integration
      # ========================================

      test "transform returns data unchanged when no presenter" do
        service = Base.new(@user)
        data = { items: [{ name: "Item" }] }

        result = service.send(:transform, data)

        assert_equal data, result
      end

      test "transform returns data unchanged when no items/resource keys" do
        service = ServiceWithPresenter.new(@user)
        data = { custom_data: [1, 2, 3] }

        result = service.send(:transform, data)

        assert_equal data, result
      end

      test "custom transform_with block overrides automatic presentation" do
        service = Class.new(Base) do
          presenter DummyPresenter

          transform_with do |data|
            { custom: "transformed" }
          end
        end.new(@user)

        data = { items: [{ name: "Item" }] }
        result = service.send(:transform, data)

        assert_equal({ custom: "transformed" }, result)
      end

      test "presenter applied during full service call" do
        service = Class.new(Base) do
          presenter DummyPresenter

          search_with do
            { items: [{ name: "Item 1" }] }
          end

          process_with do |data|
            data
          end
        end.new(@user)

        result = service.call

        assert result[:success]
        assert result[:items].all? { |i| i.is_a?(DummyPresenter) }
      end

      test "transform handles presenter initialization errors" do
        service = Class.new(Base) do
          presenter Class.new do
            def initialize(object, **options)
              raise ArgumentError, "Invalid object"
            end
          end

          search_with { { items: [{}] } }
        end.new(@user)

        result = service.call

        refute result[:success]
        assert_match(/error/i, result[:error])
      end

      test "transform works with ActiveRecord-like objects" do
        ar_object = Struct.new(:id, :name).new(1, "Record")
        service = ServiceWithPresenter.new(@user)
        data = { items: [ar_object] }

        result = service.send(:transform, data)

        assert result[:items].all? { |i| i.is_a?(DummyPresenter) }
      end

      test "presenter_options evaluated in service context" do
        service = Class.new(Base) do
          presenter DummyPresenter
          presenter_options { { user_id: user.id } }

          search_with { { items: [{ name: "Item" }] } }
        end.new(@user)

        result = service.call
        presenter = result[:items].first

        assert_equal @user.id, presenter.options[:user_id]
      end
    end
  end
end
