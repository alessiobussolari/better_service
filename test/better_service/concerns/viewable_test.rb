# frozen_string_literal: true

require "test_helper"

module BetterService
  module Concerns
    class ViewableTest < ActiveSupport::TestCase
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
        attr_reader :object

        def initialize(object, **options)
          @object = object
        end

        def name
          object[:name]&.upcase
        end
      end

      # Service with viewer enabled
      class ServiceWithViewer < Services::Base
        viewer do |processed, transformed, result|
          {
            page_title: "Test Page",
            breadcrumbs: [{ label: "Home", url: "/" }],
            actions: [:create, :edit]
          }
        end

        search_with do
          { items: [{ name: "Item 1" }] }
        end
      end

      # Service with viewer accessing service state
      class ServiceWithViewerContext < Services::Base
        viewer do |processed, transformed, result|
          {
            page_title: "Items for #{user.name}",
            user_id: user.id,
            page: params[:page]
          }
        end
      end

      def setup
        @user = DummyUser.new
      end

      # ========================================
      # Test Group 1: Viewer Configuration
      # ========================================

      test "viewer DSL sets _viewer_enabled" do
        assert ServiceWithViewer._viewer_enabled
      end

      test "viewer DSL stores _viewer_block" do
        assert_not_nil ServiceWithViewer._viewer_block
      end

      test "viewer disabled by default" do
        refute Services::Base._viewer_enabled
        assert_nil Services::Base._viewer_block
      end

      test "viewer configuration inherited by subclasses" do
        subclass = Class.new(ServiceWithViewer)

        assert subclass._viewer_enabled
        assert_not_nil subclass._viewer_block
      end

      # ========================================
      # Test Group 2: Viewer Execution
      # ========================================

      test "viewer adds :view key to result" do
        service = ServiceWithViewer.new(@user)
        result = service.call

        assert result.key?(:view)
        assert result[:view].is_a?(Hash)
      end

      test "viewer block receives processed data as first argument" do
        received_args = []
        service = Class.new(Services::Base) do
          viewer do |processed, transformed, result|
            received_args << processed
            {}
          end

          process_with { { items: [1, 2, 3] } }
        end.new(@user)

        service.call
        assert_equal [1, 2, 3], received_args.first[:items]
      end

      test "viewer block receives transformed data as second argument" do
        received_args = []
        service = Class.new(Services::Base) do
          viewer do |processed, transformed, result|
            received_args << transformed
            {}
          end

          transform_with do |data|
            { transformed: true }
          end
        end.new(@user)

        service.call
        assert received_args.first[:transformed]
      end

      test "viewer block receives result as third argument" do
        received_args = []
        service = Class.new(Services::Base) do
          viewer do |processed, transformed, result|
            received_args << result
            {}
          end
        end.new(@user)

        service.call
        assert received_args.first[:success]
      end

      test "viewer return value merged into result under :view key" do
        service = Class.new(Services::Base) do
          viewer do |processed, transformed, result|
            { page_title: "Test Page", actions: [:create, :edit] }
          end
        end.new(@user)

        result = service.call

        assert_equal "Test Page", result[:view][:page_title]
        assert_equal [:create, :edit], result[:view][:actions]
      end

      # ========================================
      # Test Group 3: Conditional Execution
      # ========================================

      test "viewer not executed when disabled" do
        service = Services::Base.new(@user)
        result = service.call

        refute result.key?(:view)
      end

      test "viewer not executed when no block" do
        service = Class.new(Services::Base) do
          self._viewer_enabled = true
          # No block defined
        end.new(@user)

        result = service.call
        refute result.key?(:view)
      end

      test "viewer_enabled? returns true when enabled with block" do
        service = ServiceWithViewer.new(@user)

        assert service.send(:viewer_enabled?)
      end

      test "viewer_enabled? returns false when no block" do
        service = Class.new(Services::Base) do
          viewer true
        end.new(@user)

        refute service.send(:viewer_enabled?)
      end

      # ========================================
      # Test Group 4: Integration & Edge Cases
      # ========================================

      test "viewer with presenter receives transformed data" do
        service = Class.new(Services::Base) do
          presenter DummyPresenter

          viewer do |processed, transformed, result|
            { presented_count: transformed[:items].count }
          end

          search_with { { items: [{ name: "Item 1" }, { name: "Item 2" }] } }
          process_with { |data| data }
        end.new(@user)

        result = service.call

        assert_equal 2, result[:view][:presented_count]
      end

      test "viewer can access service instance variables" do
        service = ServiceWithViewerContext.new(@user, params: { page: 2 })

        result = service.call

        assert_equal "Items for #{@user.name}", result[:view][:page_title]
        assert_equal @user.id, result[:view][:user_id]
        assert_equal 2, result[:view][:page]
      end

      test "viewer preserves original result data" do
        service = Class.new(Services::Base) do
          viewer do |processed, transformed, result|
            { page_title: "Test" }
          end

          respond_with do |data|
            success_result("Success", { items: [1, 2, 3], count: 3 })
          end
        end.new(@user)

        result = service.call

        assert result[:success]
        assert_equal "Success", result[:message]
        assert_equal [1, 2, 3], result[:items]
        assert_equal 3, result[:count]
        assert_equal "Test", result[:view][:page_title]
      end
    end
  end
end
