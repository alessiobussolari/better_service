# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/better_service/index_service"

module BetterService
  class IndexServiceTest < ActiveSupport::TestCase
    class User
      attr_accessor :id, :name
      def initialize(id, name)
        @id = id
        @name = name
      end
    end

    def setup
      @user = User.new(1, "Test User")
    end

    # ========================================
    # Core Behavior Tests
    # ========================================

    test "IndexService sets action_name to :index" do
      assert_equal :index, IndexService._action_name
    end

    test "IndexService returns items with metadata containing action: :index" do
      service_class = Class.new(IndexService) do
        search_with do
          { items: [1, 2, 3] }
        end
      end

      service = service_class.new(@user)
      result = service.call

      assert result[:success]
      assert_equal [1, 2, 3], result[:items]
      assert result.key?(:metadata)
      assert_equal :index, result[:metadata][:action]
    end

    test "IndexService can include stats in metadata" do
      service_class = Class.new(IndexService) do
        search_with do
          { items: [1, 2, 3] }
        end

        process_with do |data|
          {
            items: data[:items],
            metadata: {
              stats: { total: 3, average: 2 }
            }
          }
        end
      end

      service = service_class.new(@user)
      result = service.call

      assert result[:success]
      assert_equal [1, 2, 3], result[:items]
      assert_equal :index, result[:metadata][:action]
      assert_equal 3, result[:metadata][:stats][:total]
      assert_equal 2, result[:metadata][:stats][:average]
    end

    test "IndexService can include pagination in metadata" do
      service_class = Class.new(IndexService) do
        search_with do
          { items: (1..25).to_a }
        end

        process_with do |data|
          page = params[:page] || 1
          per_page = 10
          offset = (page - 1) * per_page

          {
            items: data[:items][offset, per_page],
            metadata: {
              pagination: {
                current_page: page,
                total_pages: (data[:items].size / per_page.to_f).ceil,
                total_count: data[:items].size
              }
            }
          }
        end
      end

      service = service_class.new(@user, params: { page: 2 })
      result = service.call

      assert result[:success]
      assert_equal 10, result[:items].size
      assert_equal 11, result[:items].first
      assert_equal :index, result[:metadata][:action]
      assert_equal 2, result[:metadata][:pagination][:current_page]
      assert_equal 3, result[:metadata][:pagination][:total_pages]
      assert_equal 25, result[:metadata][:pagination][:total_count]
    end

    test "IndexService can include both stats and pagination in metadata" do
      service_class = Class.new(IndexService) do
        search_with do
          { items: [1, 2, 3, 4, 5] }
        end

        process_with do |data|
          {
            items: data[:items],
            metadata: {
              stats: { count: data[:items].size },
              pagination: { page: 1, per_page: 10 }
            }
          }
        end
      end

      service = service_class.new(@user)
      result = service.call

      assert result[:success]
      assert_equal :index, result[:metadata][:action]
      assert_equal 5, result[:metadata][:stats][:count]
      assert_equal 1, result[:metadata][:pagination][:page]
    end

    test "IndexService works with empty items" do
      service_class = Class.new(IndexService) do
        search_with do
          { items: [] }
        end
      end

      service = service_class.new(@user)
      result = service.call

      assert result[:success]
      assert_equal [], result[:items]
      assert_equal :index, result[:metadata][:action]
    end

    test "IndexService can apply presenter to items" do
      test_presenter = Class.new do
        def initialize(item, _options = {})
          @item = item
        end

        def to_h
          { value: @item * 2 }
        end
      end

      service_class = Class.new(IndexService) do
        self.presenter test_presenter

        search_with do
          { items: [1, 2, 3] }
        end
      end

      service = service_class.new(@user)
      result = service.call

      assert result[:success]
      assert_equal 3, result[:items].size
      assert result[:items].all? { |i| i.is_a?(test_presenter) }
      assert_equal 2, result[:items].first.to_h[:value]
      assert_equal 4, result[:items].second.to_h[:value]
      assert_equal 6, result[:items].third.to_h[:value]
    end

    # ========================================
    # Integration Tests
    # ========================================

    test "IndexService integrates with Validatable" do
      service_class = Class.new(IndexService) do
        schema do
          optional(:page).filled(:integer, gteq?: 1)
        end

        search_with do
          { items: [1, 2, 3] }
        end
      end

      # Valid params
      service = service_class.new(@user, params: { page: 1 })
      result = service.call
      assert result[:success]

      # Invalid params
      service = service_class.new(@user, params: { page: 0 })
      result = service.call
      refute result[:success]
      assert_equal "Validation failed", result[:error]
    end

    test "IndexService integrates with Viewable" do
      service_class = Class.new(IndexService) do
        viewer do |processed, _transformed, _result|
          {
            page_title: "Index Page",
            breadcrumbs: [{ label: "Home", url: "/" }]
          }
        end

        search_with do
          { items: [1, 2, 3] }
        end
      end

      service = service_class.new(@user)
      result = service.call

      assert result[:success]
      assert result.key?(:view)
      assert_equal "Index Page", result[:view][:page_title]
    end
  end
end
