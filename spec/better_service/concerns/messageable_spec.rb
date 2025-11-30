# frozen_string_literal: true

require "rails_helper"

module BetterService
  module Concerns
    RSpec.describe "Messageable concern" do
      let(:dummy_user_class) do
        Class.new do
          attr_accessor :id, :name

          def initialize(id: 1, name: "Test User")
            @id = id
            @name = name
          end
        end
      end

      let(:user) { dummy_user_class.new }

      let(:base_service_without_namespace_class) do
        Class.new(Services::Base) do
          self._allow_nil_user = true
        end
      end

      let(:booking_service_class) do
        Class.new(Services::Base) do
          messages_namespace :bookings

          search_with do
            { items: [] }
          end
        end
      end

      before do
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

      describe "basic message resolution" do
        it "returns key when no namespace configured" do
          service = base_service_without_namespace_class.new(nil)
          result = service.send(:message, "success.created")

          expect(result).to eq("success.created")
        end

        it "builds correct I18n key with namespace" do
          service = booking_service_class.new(user)
          result = service.send(:message, "success.created")

          expect(result).to eq("Booking created!")
        end

        it "passes interpolations to I18n" do
          service = booking_service_class.new(user)
          result = service.send(:message, "errors.not_found", id: 123)

          expect(result).to eq("Booking 123 not found")
        end

        it "messages_namespace sets _messages_namespace attribute" do
          expect(booking_service_class._messages_namespace).to eq(:bookings)
        end
      end

      describe "inheritance" do
        it "messages_namespace is inherited by subclasses" do
          subclass = Class.new(booking_service_class)
          expect(subclass._messages_namespace).to eq(:bookings)
        end

        it "subclass can override messages_namespace" do
          subclass = Class.new(booking_service_class) do
            messages_namespace :articles
          end

          expect(subclass._messages_namespace).to eq(:articles)
        end

        it "_messages_namespace defaults to nil" do
          expect(base_service_without_namespace_class._messages_namespace).to be_nil
        end
      end

      describe "integration with service flow" do
        it "message works in search phase" do
          service_class = Class.new(Services::Base) do
            messages_namespace :bookings

            search_with do
              msg = message("success.created")
              { search_message: msg }
            end

            respond_with do |data|
              { object: nil, success: true, metadata: { search_message: data[:search_message] } }
            end
          end

          _object, meta = service_class.new(user).call

          expect(meta[:success]).to be true
          expect(meta[:search_message]).to eq("Booking created!")
        end

        it "message works in respond phase" do
          service_class = Class.new(Services::Base) do
            messages_namespace :bookings

            respond_with do |data|
              success_result(message("success.created"), data)
            end
          end

          _object, meta = service_class.new(user).call

          expect(meta[:message]).to eq("Booking created!")
        end

        it "message resolves real translation" do
          service = booking_service_class.new(user)
          result = service.send(:message, "success.created")

          expect(result).to eq("Booking created!")
        end

        it "message returns key itself when translation not found" do
          service = booking_service_class.new(user)
          result = service.send(:message, "nonexistent.key")

          expect(result).to eq("nonexistent.key")
        end

        it "message handles complex interpolations" do
          service = booking_service_class.new(user)
          result = service.send(:message, "success.updated", id: 123, user: "John")

          expect(result).to eq("Booking 123 updated by John")
        end
      end
    end
  end
end
