# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/better_service/services/update_service"

module BetterService
  class UpdateServiceTest < ActiveSupport::TestCase
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

    test "UpdateService sets action_name to :updated" do
      assert_equal :updated, Services::UpdateService._action_name
    end

    test "UpdateService has transactions enabled by default" do
      assert Services::UpdateService._with_transaction
    end

    test "UpdateService has auto_invalidate_cache enabled by default" do
      assert Services::UpdateService._auto_invalidate_cache
    end

    test "UpdateService has default schema requiring id" do
      service_class = Class.new(Services::UpdateService) do
        search_with do
          { resource: { id: params[:id] } }
        end

        process_with do |data|
          data
        end
      end

      # Valid params with id
      service = service_class.new(@user, params: { id: 1 })
      result = service.call
      assert result[:success]
    end

    test "UpdateService validates id param is required" do
      service_class = Class.new(Services::UpdateService) do
        search_with do
          { resource: { id: params[:id] } }
        end

        process_with do |data|
          data
        end
      end

      # Invalid params - should raise during initialize
      error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
        service_class.new(@user, params: {})
      end

      assert_equal :validation_failed, error.code
      assert error.context[:validation_errors].key?(:id)
    end

    test "UpdateService returns resource with metadata containing action: :updated" do
      service_class = Class.new(Services::UpdateService) do
        search_with do
          { resource: { id: params[:id], title: "Original" } }
        end

        process_with do |data|
          { resource: data[:resource].merge(title: "Updated") }
        end
      end

      service = service_class.new(@user, params: { id: 1 })
      result = service.call

      assert result[:success]
      assert_equal({ id: 1, title: "Updated" }, result[:resource])
      assert result.key?(:metadata)
      assert_equal :updated, result[:metadata][:action]
    end

    test "UpdateService message defaults to updated successfully" do
      service_class = Class.new(Services::UpdateService) do
        search_with do
          { resource: { id: params[:id] } }
        end

        process_with do |data|
          data
        end
      end

      service = service_class.new(@user, params: { id: 1 })
      result = service.call

      assert result[:success]
      assert_equal "Resource updated successfully", result[:message]
    end

    test "UpdateService custom respond_with overrides default message" do
      service_class = Class.new(Services::UpdateService) do
        search_with do
          { resource: { id: params[:id] } }
        end

        process_with do |data|
          data
        end

        respond_with do |data|
          success_result("Custom update message", data)
        end
      end

      service = service_class.new(@user, params: { id: 1 })
      result = service.call

      assert result[:success]
      assert_equal "Custom update message", result[:message]
    end

    test "UpdateService ensures resource key exists in result" do
      service_class = Class.new(Services::UpdateService) do
        search_with do
          {}
        end

        process_with do |_data|
          {} # No resource key
        end
      end

      service = service_class.new(@user, params: { id: 1 })
      result = service.call

      assert result[:success]
      assert result.key?(:resource)
      assert_nil result[:resource]
    end

    test "UpdateService with custom schema validates additional params" do
      service_class = Class.new(Services::UpdateService) do
        schema do
          required(:id).filled
          required(:title).filled(:string)
        end

        search_with do
          { resource: { id: params[:id] } }
        end

        process_with do |data|
          { resource: data[:resource].merge(title: params[:title]) }
        end
      end

      # Valid params
      service = service_class.new(@user, params: { id: 1, title: "New Title" })
      result = service.call
      assert result[:success]
      assert_equal "New Title", result[:resource][:title]

      # Invalid params - missing title
      error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
        service_class.new(@user, params: { id: 1 })
      end

      assert_equal :validation_failed, error.code
      assert error.context[:validation_errors].key?(:title)
    end
  end
end
