# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/better_service/services/show_service"

module BetterService
  class ShowServiceTest < ActiveSupport::TestCase
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

    test "ShowService sets action_name to :show" do
      assert_equal :show, Services::ShowService._action_name
    end

    test "ShowService returns resource with metadata containing action: :show" do
      service_class = Class.new(Services::ShowService) do
        search_with do
          { resource: { id: 1, title: "Test" } }
        end
      end

      service = service_class.new(@user, params: { id: 1 })
      result = service.call

      assert result[:success]
      assert_equal({ id: 1, title: "Test" }, result[:resource])
      assert result.key?(:metadata)
      assert_equal :show, result[:metadata][:action]
    end

    test "ShowService can include additional metadata" do
      service_class = Class.new(Services::ShowService) do
        search_with do
          { resource: { id: 1, title: "Test" } }
        end

        process_with do |data|
          {
            resource: data[:resource],
            metadata: {
              last_modified: Time.now.iso8601
            }
          }
        end
      end

      service = service_class.new(@user, params: { id: 1 })
      result = service.call

      assert result[:success]
      assert_equal :show, result[:metadata][:action]
      assert result[:metadata].key?(:last_modified)
    end

    test "ShowService integrates with Validatable" do
      service_class = Class.new(Services::ShowService) do
        schema do
          required(:id).filled(:integer, gteq?: 1)
        end

        search_with do
          { resource: { id: params[:id], title: "Test" } }
        end
      end

      # Valid params
      service = service_class.new(@user, params: { id: 1 })
      result = service.call
      assert result[:success]

      # Invalid params - should raise during initialize
      error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
        service_class.new(@user, params: { id: 0 })
      end
      assert_equal :validation_failed, error.code
    end

    test "ShowService integrates with Viewable" do
      service_class = Class.new(Services::ShowService) do
        viewer do |processed, _transformed, _result|
          {
            page_title: "Show Page",
            breadcrumbs: [{ label: "Home", url: "/" }, { label: "Show", url: "#" }]
          }
        end

        search_with do
          { resource: { id: 1, title: "Test" } }
        end
      end

      service = service_class.new(@user, params: { id: 1 })
      result = service.call

      assert result[:success]
      assert result.key?(:view)
      assert_equal "Show Page", result[:view][:page_title]
    end

    test "ShowService can apply presenter to resource" do
      test_presenter = Class.new do
        def initialize(resource, _options = {})
          @resource = resource
        end

        def to_h
          { display_name: "Item ##{@resource[:id]}" }
        end
      end

      service_class = Class.new(Services::ShowService) do
        self.presenter test_presenter

        search_with do
          { resource: { id: 123 } }
        end
      end

      service = service_class.new(@user, params: { id: 123 })
      result = service.call

      assert result[:success]
      assert result[:resource].is_a?(test_presenter)
      assert_equal "Item #123", result[:resource].to_h[:display_name]
    end
  end
end
