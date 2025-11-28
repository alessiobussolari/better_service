# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/better_service/services/destroy_service"

module BetterService
  class DestroyServiceTest < ActiveSupport::TestCase
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

    test "DestroyService sets action_name to :deleted" do
      assert_equal :deleted, Services::DestroyService._action_name
    end

    test "DestroyService has transactions enabled by default" do
      assert Services::DestroyService._with_transaction
    end

    test "DestroyService has auto_invalidate_cache enabled by default" do
      assert Services::DestroyService._auto_invalidate_cache
    end

    test "DestroyService has default schema requiring id" do
      service_class = Class.new(Services::DestroyService) do
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

    test "DestroyService validates id param is required" do
      service_class = Class.new(Services::DestroyService) do
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

    test "DestroyService returns resource with metadata containing action: :deleted" do
      service_class = Class.new(Services::DestroyService) do
        search_with do
          { resource: { id: params[:id], title: "To Delete" } }
        end

        process_with do |data|
          { resource: data[:resource] }
        end
      end

      service = service_class.new(@user, params: { id: 1 })
      result = service.call

      assert result[:success]
      assert_equal({ id: 1, title: "To Delete" }, result[:resource])
      assert result.key?(:metadata)
      assert_equal :deleted, result[:metadata][:action]
    end

    test "DestroyService message defaults to deleted successfully" do
      service_class = Class.new(Services::DestroyService) do
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
      assert_equal "Resource deleted successfully", result[:message]
    end

    test "DestroyService custom respond_with overrides default message" do
      service_class = Class.new(Services::DestroyService) do
        search_with do
          { resource: { id: params[:id] } }
        end

        process_with do |data|
          data
        end

        respond_with do |data|
          success_result("Custom delete message", data)
        end
      end

      service = service_class.new(@user, params: { id: 1 })
      result = service.call

      assert result[:success]
      assert_equal "Custom delete message", result[:message]
    end

    test "DestroyService ensures resource key exists in result" do
      service_class = Class.new(Services::DestroyService) do
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

    test "DestroyService with custom schema validates additional params" do
      service_class = Class.new(Services::DestroyService) do
        schema do
          required(:id).filled
          optional(:soft_delete).filled(:bool)
        end

        search_with do
          { resource: { id: params[:id] } }
        end

        process_with do |data|
          {
            resource: data[:resource],
            soft_deleted: params[:soft_delete] || false
          }
        end
      end

      # Valid params with optional soft_delete
      service = service_class.new(@user, params: { id: 1, soft_delete: true })
      result = service.call
      assert result[:success]
      assert result[:soft_deleted]

      # Valid params without optional soft_delete
      service = service_class.new(@user, params: { id: 1 })
      result = service.call
      assert result[:success]
      refute result[:soft_deleted]
    end

    test "DestroyService inherits from Base" do
      assert Services::DestroyService < Services::Base
    end
  end
end
