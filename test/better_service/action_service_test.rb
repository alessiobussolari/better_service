# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/better_service/services/action_service"

module BetterService
  class ActionServiceTest < ActiveSupport::TestCase
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

    test "ActionService default action_name is nil" do
      assert_nil Services::ActionService._action_name
    end

    test "ActionService allows setting custom action_name" do
      service_class = Class.new(Services::ActionService) do
        action_name :approved

        search_with do
          { resource: { id: 1, status: "pending" } }
        end

        process_with do |data|
          resource = data[:resource].dup
          resource[:status] = "approved"
          { resource: resource }
        end
      end

      assert_equal :approved, service_class._action_name

      service = service_class.new(@user, params: { id: 1 })
      result = service.call

      assert result[:success]
      assert_equal "approved", result[:resource][:status]
      assert result.key?(:metadata)
      assert_equal :approved, result[:metadata][:action]
    end

    test "ActionService supports multiple different actions" do
      accept_service = Class.new(Services::ActionService) do
        action_name :accepted

        search_with { { resource: { id: 1 } } }
        process_with { |data| { resource: data[:resource].merge(status: "accepted") } }
      end

      reject_service = Class.new(Services::ActionService) do
        action_name :rejected

        search_with { { resource: { id: 1 } } }
        process_with { |data| { resource: data[:resource].merge(status: "rejected") } }
      end

      assert_equal :accepted, accept_service._action_name
      assert_equal :rejected, reject_service._action_name

      result1 = accept_service.new(@user, params: { id: 1 }).call
      assert_equal :accepted, result1[:metadata][:action]

      result2 = reject_service.new(@user, params: { id: 1 }).call
      assert_equal :rejected, result2[:metadata][:action]
    end

    test "ActionService message defaults to action completed successfully" do
      service_class = Class.new(Services::ActionService) do
        action_name :published

        search_with { { resource: { id: 1 } } }
        process_with { |data| { resource: data[:resource] } }
      end

      service = service_class.new(@user, params: { id: 1 })
      result = service.call

      assert result[:success]
      assert_equal "Action completed successfully", result[:message]
    end
  end
end
