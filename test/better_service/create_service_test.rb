# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/better_service/create_service"

module BetterService
  class CreateServiceTest < ActiveSupport::TestCase
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

    test "CreateService sets action_name to :created" do
      assert_equal :created, CreateService._action_name
    end

    test "CreateService returns resource with metadata containing action: :created" do
      service_class = Class.new(CreateService) do
        search_with do
          {}
        end

        process_with do |_data|
          { resource: { id: 1, title: "New Item" } }
        end
      end

      service = service_class.new(@user, params: { title: "New Item" })
      result = service.call

      assert result[:success]
      assert_equal({ id: 1, title: "New Item" }, result[:resource])
      assert result.key?(:metadata)
      assert_equal :created, result[:metadata][:action]
    end

    test "CreateService validates params before processing" do
      service_class = Class.new(CreateService) do
        schema do
          required(:title).filled(:string)
        end

        search_with do
          {}
        end

        process_with do |_data|
          { resource: { id: 1, title: params[:title] } }
        end
      end

      # Invalid params
      service = service_class.new(@user, params: {})
      result = service.call

      refute result[:success]
      assert_equal "Validation failed", result[:error]
    end

    test "CreateService message defaults to created successfully" do
      service_class = Class.new(CreateService) do
        search_with do
          {}
        end

        process_with do |_data|
          { resource: { id: 1 } }
        end
      end

      service = service_class.new(@user)
      result = service.call

      assert result[:success]
      assert_equal "Resource created successfully", result[:message]
    end
  end
end
