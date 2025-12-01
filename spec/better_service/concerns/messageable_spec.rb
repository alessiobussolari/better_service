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

      describe "#extract_action_from_key" do
        let(:service) { base_service_without_namespace_class.new(nil) }

        it "extracts 'created' from create key" do
          result = service.send(:extract_action_from_key, "create.success")
          expect(result).to eq("created")
        end

        it "extracts 'created' from CREATE key (case insensitive)" do
          result = service.send(:extract_action_from_key, "CREATE.success")
          expect(result).to eq("created")
        end

        it "extracts 'updated' from update key" do
          result = service.send(:extract_action_from_key, "update.success")
          expect(result).to eq("updated")
        end

        it "extracts 'deleted' from destroy key" do
          result = service.send(:extract_action_from_key, "destroy.success")
          expect(result).to eq("deleted")
        end

        it "extracts 'deleted' from delete key" do
          result = service.send(:extract_action_from_key, "delete.success")
          expect(result).to eq("deleted")
        end

        it "extracts 'listed' from index key" do
          result = service.send(:extract_action_from_key, "index.success")
          expect(result).to eq("listed")
        end

        it "extracts 'listed' from list key" do
          result = service.send(:extract_action_from_key, "list.success")
          expect(result).to eq("listed")
        end

        it "extracts 'shown' from show key" do
          result = service.send(:extract_action_from_key, "show.success")
          expect(result).to eq("shown")
        end

        it "returns 'action_completed' for unknown actions" do
          result = service.send(:extract_action_from_key, "custom_action.success")
          expect(result).to eq("action_completed")
        end

        it "returns 'action_completed' for empty string" do
          result = service.send(:extract_action_from_key, "")
          expect(result).to eq("action_completed")
        end
      end

      describe "#failure_for" do
        let(:mock_record_class) do
          Class.new do
            attr_accessor :errors

            def initialize(new_record: true)
              @new_record = new_record
              @errors = { name: [ "can't be blank" ] }
            end

            def new_record?
              @new_record
            end

            def self.name
              "TestRecord"
            end
          end
        end

        let(:service) { base_service_without_namespace_class.new(nil) }

        it "builds failure response hash" do
          record = mock_record_class.new
          result = service.send(:failure_for, record)

          expect(result[:success]).to be false
          expect(result[:object]).to eq(record)
          expect(result[:message]).to be_a(String)
        end

        it "uses custom message when provided" do
          record = mock_record_class.new
          result = service.send(:failure_for, record, "Custom failure message")

          expect(result[:message]).to eq("Custom failure message")
        end

        it "uses default failure message when no custom message" do
          record = mock_record_class.new
          result = service.send(:failure_for, record)

          expect(result[:message]).not_to be_nil
          expect(result[:message]).to be_a(String)
        end
      end

      describe "#success_for" do
        let(:service) { base_service_without_namespace_class.new(nil) }

        it "builds success response hash" do
          object = { id: 1, name: "Test" }
          result = service.send(:success_for, object)

          expect(result[:success]).to be true
          expect(result[:object]).to eq(object)
          expect(result[:message]).to be_a(String)
        end

        it "uses custom message when provided" do
          object = { id: 1 }
          result = service.send(:success_for, object, "Custom success message")

          expect(result[:message]).to eq("Custom success message")
        end

        it "uses default success message when no custom message" do
          object = { id: 1 }
          result = service.send(:success_for, object)

          expect(result[:message]).not_to be_nil
        end

        it "handles nil object" do
          result = service.send(:success_for, nil)

          expect(result[:success]).to be true
          expect(result[:object]).to be_nil
        end
      end

      describe "#default_failure_message" do
        let(:mock_record_class) do
          Class.new do
            def initialize(new_record: true)
              @new_record = new_record
            end

            def new_record?
              @new_record
            end

            def self.name
              "Product"
            end
          end
        end

        let(:service) { base_service_without_namespace_class.new(nil) }

        it "returns create failure message for new record" do
          record = mock_record_class.new(new_record: true)
          result = service.send(:default_failure_message, record)

          expect(result).to include("create")
        end

        it "returns update failure message for existing record" do
          record = mock_record_class.new(new_record: false)
          result = service.send(:default_failure_message, record)

          expect(result).to include("update")
        end

        it "humanizes model name in message" do
          record = mock_record_class.new
          result = service.send(:default_failure_message, record)

          expect(result.downcase).to include("product")
        end
      end

      describe "#default_success_message" do
        let(:service_with_action) do
          klass = Class.new(Services::Base) do
            self._allow_nil_user = true
            performed_action :create
          end
          klass.new(nil)
        end

        let(:service_without_action) do
          klass = Class.new(Services::Base) do
            self._allow_nil_user = true
          end
          klass.new(nil)
        end

        it "uses action name in message when defined" do
          result = service_with_action.send(:default_success_message)
          expect(result).to be_a(String)
        end

        it "uses default action in message when not defined" do
          result = service_without_action.send(:default_success_message)
          expect(result).to be_a(String)
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
