# frozen_string_literal: true

require "test_helper"

module BetterService
  module Concerns
    class MessageableTest < ActiveSupport::TestCase
      # Dummy user class for testing
      class DummyUser
        attr_accessor :id, :name

        def initialize(id: 1, name: "Test User")
          @id = id
          @name = name
        end
      end

      # Service without namespace
      class BaseServiceWithoutNamespace < Services::Base
        self._allow_nil_user = true
      end

      # Service with namespace configured
      class BookingService < Services::Base
        messages_namespace :bookings

        search_with do
          { items: [] }
        end
      end

      def setup
        @user = DummyUser.new
        I18n.backend.store_translations(:en, {
          bookings: {
            services: {
              success: {
                created: "Booking created!",
                updated: "Booking %{id} updated by %{user}"
              },
              errors: {
                not_found: "Booking %{id} not found"
              }
            }
          }
        })
      end

      # ========================================
      # Test Group 1: Basic Message Resolution
      # ========================================

      test "message returns key when no namespace configured" do
        service = BaseServiceWithoutNamespace.new(nil)
        result = service.send(:message, "success.created")

        assert_equal "success.created", result
      end

      test "message builds correct I18n key with namespace" do
        service = BookingService.new(@user)
        result = service.send(:message, "success.created")

        assert_equal "Booking created!", result
      end

      test "message passes interpolations to I18n" do
        service = BookingService.new(@user)
        result = service.send(:message, "errors.not_found", id: 123)

        assert_equal "Booking 123 not found", result
      end

      test "messages_namespace sets _messages_namespace attribute" do
        assert_equal :bookings, BookingService._messages_namespace
      end

      # ========================================
      # Test Group 2: Inheritance
      # ========================================

      test "messages_namespace is inherited by subclasses" do
        subclass = Class.new(BookingService)

        assert_equal :bookings, subclass._messages_namespace
      end

      test "subclass can override messages_namespace" do
        subclass = Class.new(BookingService) do
          messages_namespace :articles
        end

        assert_equal :articles, subclass._messages_namespace
      end

      test "_messages_namespace defaults to nil" do
        assert_nil BaseServiceWithoutNamespace._messages_namespace
      end

      # ========================================
      # Test Group 3: Integration with Service Flow
      # ========================================

      test "message works in search phase" do
        service = Class.new(Services::Base) do
          messages_namespace :bookings

          search_with do
            msg = message("success.created")
            { search_message: msg }
          end
        end.new(@user)

        result = service.call

        assert result[:success]
        assert_equal "Booking created!", result[:search_message]
      end

      test "message works in respond phase" do
        service = Class.new(Services::Base) do
          messages_namespace :bookings

          respond_with do |data|
            success_result(message("success.created"), data)
          end
        end.new(@user)

        result = service.call

        assert_equal "Booking created!", result[:message]
      end

      test "message resolves real translation" do
        service = BookingService.new(@user)
        result = service.send(:message, "success.created")

        assert_equal "Booking created!", result
      end

      test "message returns missing translation key on failure" do
        service = BookingService.new(@user)
        result = service.send(:message, "nonexistent.key")

        assert_match(/translation missing/i, result)
      end

      test "message handles complex interpolations" do
        service = BookingService.new(@user)
        result = service.send(:message, "success.updated", id: 123, user: "John")

        assert_equal "Booking 123 updated by John", result
      end
    end
  end
end
