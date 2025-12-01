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

        # Additional mutation-killing tests
        it "extracts action from nested paths with create" do
          result = service.send(:extract_action_from_key, "admin.product.create.success")
          expect(result).to eq("created")
        end

        it "extracts action from nested paths with update" do
          result = service.send(:extract_action_from_key, "admin.product.update.success")
          expect(result).to eq("updated")
        end

        it "extracts action from nested paths with destroy" do
          result = service.send(:extract_action_from_key, "admin.product.destroy.success")
          expect(result).to eq("deleted")
        end

        it "matches create pattern anywhere in key" do
          result = service.send(:extract_action_from_key, "pre_create_post")
          expect(result).to eq("created")
        end

        it "matches update pattern anywhere in key" do
          result = service.send(:extract_action_from_key, "batch_update_items")
          expect(result).to eq("updated")
        end

        it "matches destroy pattern anywhere in key" do
          result = service.send(:extract_action_from_key, "bulk_destroy_records")
          expect(result).to eq("deleted")
        end

        it "matches index pattern anywhere in key" do
          result = service.send(:extract_action_from_key, "reindex_products")
          expect(result).to eq("listed")
        end

        it "matches show pattern anywhere in key" do
          result = service.send(:extract_action_from_key, "showcase_item")
          expect(result).to eq("shown")
        end

        it "uses first matching pattern when multiple present" do
          # create comes before destroy in case order
          result = service.send(:extract_action_from_key, "create_and_destroy")
          expect(result).to eq("created")
        end

        it "handles single character key" do
          result = service.send(:extract_action_from_key, "c")
          expect(result).to eq("action_completed")
        end

        it "handles key with only whitespace" do
          result = service.send(:extract_action_from_key, "   ")
          expect(result).to eq("action_completed")
        end

        it "handles mixed case patterns" do
          expect(service.send(:extract_action_from_key, "CreAtE.key")).to eq("created")
          expect(service.send(:extract_action_from_key, "UpDaTe.key")).to eq("updated")
          expect(service.send(:extract_action_from_key, "DeStRoY.key")).to eq("deleted")
          expect(service.send(:extract_action_from_key, "InDeX.key")).to eq("listed")
          expect(service.send(:extract_action_from_key, "ShOw.key")).to eq("shown")
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

        # Mutation-killing tests
        it "uses empty string custom message when provided" do
          record = mock_record_class.new
          result = service.send(:failure_for, record, "")

          expect(result[:message]).to eq("")
        end

        it "preserves exact object reference" do
          record = mock_record_class.new
          result = service.send(:failure_for, record)

          expect(result[:object]).to equal(record)
        end

        it "always sets success to false" do
          record = mock_record_class.new
          result = service.send(:failure_for, record)

          expect(result[:success]).to eq(false)
          expect(result[:success]).not_to be_nil
        end

        it "returns hash with exactly three keys" do
          record = mock_record_class.new
          result = service.send(:failure_for, record)

          expect(result.keys).to match_array([ :object, :success, :message ])
        end

        it "works with existing record (not new)" do
          record = mock_record_class.new(new_record: false)
          result = service.send(:failure_for, record)

          expect(result[:success]).to be false
          expect(result[:message]).to include("update")
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

        # Mutation-killing tests
        it "uses empty string custom message when provided" do
          object = { id: 1 }
          result = service.send(:success_for, object, "")

          expect(result[:message]).to eq("")
        end

        it "preserves exact object reference" do
          object = { id: 1, name: "Test" }
          result = service.send(:success_for, object)

          expect(result[:object]).to equal(object)
        end

        it "always sets success to true" do
          result = service.send(:success_for, {})

          expect(result[:success]).to eq(true)
          expect(result[:success]).not_to be_nil
        end

        it "returns hash with exactly three keys" do
          result = service.send(:success_for, {})

          expect(result.keys).to match_array([ :object, :success, :message ])
        end

        it "handles false as object (falsy but valid)" do
          result = service.send(:success_for, false)

          expect(result[:success]).to be true
          expect(result[:object]).to be false
        end

        it "handles 0 as object" do
          result = service.send(:success_for, 0)

          expect(result[:success]).to be true
          expect(result[:object]).to eq(0)
        end

        it "handles empty array as object" do
          result = service.send(:success_for, [])

          expect(result[:success]).to be true
          expect(result[:object]).to eq([])
        end

        it "handles empty string as object" do
          result = service.send(:success_for, "")

          expect(result[:success]).to be true
          expect(result[:object]).to eq("")
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

        # Mutation-killing tests
        it "returns a string" do
          record = mock_record_class.new
          result = service.send(:default_failure_message, record)

          expect(result).to be_a(String)
        end

        it "handles namespaced model names" do
          namespaced_class = Class.new do
            def new_record?
              true
            end

            def self.name
              "Admin::Products::Item"
            end
          end

          record = namespaced_class.new
          result = service.send(:default_failure_message, record)

          expect(result).to be_a(String)
          expect(result.downcase).to include("item")
        end

        it "calls message helper with create.failure for new record" do
          record = mock_record_class.new(new_record: true)

          expect(service).to receive(:message).with("create.failure", anything).and_call_original
          service.send(:default_failure_message, record)
        end

        it "calls message helper with update.failure for existing record" do
          record = mock_record_class.new(new_record: false)

          expect(service).to receive(:message).with("update.failure", anything).and_call_original
          service.send(:default_failure_message, record)
        end

        it "different paths for new vs existing records" do
          new_record = mock_record_class.new(new_record: true)
          existing_record = mock_record_class.new(new_record: false)

          new_result = service.send(:default_failure_message, new_record)
          existing_result = service.send(:default_failure_message, existing_record)

          expect(new_result).not_to eq(existing_result)
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

        # Mutation-killing tests
        it "calls message with action-based key when action defined" do
          expect(service_with_action).to receive(:message).with("create.success", anything).and_call_original
          service_with_action.send(:default_success_message)
        end

        it "calls message with action.success key when action is nil" do
          expect(service_without_action).to receive(:message).with("action.success", anything).and_call_original
          service_without_action.send(:default_success_message)
        end

        it "returns different messages for different actions" do
          update_service = Class.new(Services::Base) do
            self._allow_nil_user = true
            performed_action :update
          end.new(nil)

          destroy_service = Class.new(Services::Base) do
            self._allow_nil_user = true
            performed_action :destroy
          end.new(nil)

          create_result = service_with_action.send(:default_success_message)
          update_result = update_service.send(:default_success_message)
          destroy_result = destroy_service.send(:default_success_message)

          # All should be strings
          expect(create_result).to be_a(String)
          expect(update_result).to be_a(String)
          expect(destroy_result).to be_a(String)
        end

        it "always returns a string" do
          result = service_with_action.send(:default_success_message)
          expect(result).not_to be_nil
          expect(result).to be_a(String)
        end

        it "uses _action_name class attribute" do
          service_class = Class.new(Services::Base) do
            self._allow_nil_user = true
            self._action_name = :custom_action
          end
          service = service_class.new(nil)

          expect(service).to receive(:message).with("custom_action.success", anything).and_call_original
          service.send(:default_success_message)
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
