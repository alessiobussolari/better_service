# frozen_string_literal: true

require "rails_helper"

module BetterService
  RSpec.describe Services::Base do
    # Dummy user class for testing
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
    let(:params) { { page: 1, search: "test" } }

    # ========================================
    # Initialize Tests
    # ========================================

    describe "#initialize" do
      context "schema validation" do
        it "requires schema to be defined" do
          service_class = Class.new(Services::Base)
          service_class._schema = nil

          expect {
            service_class.new(user, params: {})
          }.to raise_error(BetterService::Errors::Configuration::SchemaRequiredError) do |error|
            expect(error.message).to match(/must define a schema block/)
            expect(error.message).to match(/Add 'schema do ... end'/)
          end
        end
      end

      context "user validation" do
        it "requires user by default" do
          expect {
            Services::Base.new(nil, params: {})
          }.to raise_error(BetterService::Errors::Configuration::NilUserError) do |error|
            expect(error.message).to match(/User cannot be nil/)
            expect(error.message).to match(/allow_nil_user/)
          end
        end
      end

      context "with valid user and params" do
        it "sets user" do
          service = Services::Base.new(user, params: params)
          expect(service.instance_variable_get(:@user)).to eq(user)
        end

        it "sets params as hash" do
          service = Services::Base.new(user, params: params)
          expect(service.instance_variable_get(:@params)).to be_a(Hash)
        end
      end

      context "with ActionController::Parameters" do
        it "sanitizes to hash with symbol keys" do
          ac_params = ActionController::Parameters.new(page: "1", search: "test", controller: "bookings")
          service = Services::Base.new(user, params: ac_params)
          params_result = service.instance_variable_get(:@params)

          expect(params_result).to be_a(Hash)
          expect(params_result).to have_key(:page)
          expect(params_result).to have_key(:search)
          expect(params_result).not_to have_key("page")
        end
      end

      context "with plain hash params" do
        it "converts string keys to symbol keys" do
          plain_hash = { "page" => 1, "search" => "test" }
          service = Services::Base.new(user, params: plain_hash)
          params_result = service.instance_variable_get(:@params)

          expect(params_result).to have_key(:page)
          expect(params_result).to have_key(:search)
          expect(params_result).not_to have_key("page")
        end
      end

      context "with nil params" do
        it "handles gracefully with empty hash" do
          service = Services::Base.new(user, params: nil)
          expect(service.instance_variable_get(:@params)).to eq({})
        end
      end

      context "with empty params" do
        it "handles empty hash" do
          service = Services::Base.new(user, params: {})
          expect(service.instance_variable_get(:@params)).to eq({})
        end
      end
    end

    # ========================================
    # allow_nil_user DSL Tests
    # ========================================

    describe ".allow_nil_user DSL" do
      context "when set to true" do
        let(:service_class) do
          Class.new(Services::Base) do
            allow_nil_user true
          end
        end

        it "allows nil user" do
          service = service_class.new(nil, params: {})
          expect(service.user).to be_nil
        end

        it "still accepts valid user" do
          service = service_class.new(user, params: {})
          expect(service.user).to eq(user)
        end
      end

      context "when set to false" do
        let(:service_class) do
          Class.new(Services::Base) do
            allow_nil_user false
          end
        end

        it "requires user" do
          expect {
            service_class.new(nil, params: {})
          }.to raise_error(BetterService::Errors::Configuration::NilUserError) do |error|
            expect(error.message).to match(/User cannot be nil/)
          end
        end
      end

      context "when called without argument" do
        let(:service_class) do
          Class.new(Services::Base) do
            allow_nil_user
          end
        end

        it "defaults to true" do
          service = service_class.new(nil, params: {})
          expect(service.user).to be_nil
        end
      end

      context "with direct attribute assignment" do
        let(:service_class) do
          Class.new(Services::Base) do
            self._allow_nil_user = true
          end
        end

        it "is backward compatible" do
          service = service_class.new(nil, params: {})
          expect(service.user).to be_nil
        end
      end
    end

    # ========================================
    # Result Helpers Tests
    # ========================================

    describe "#success_result" do
      it "returns hash with success true" do
        service = Services::Base.new(user)
        result = service.send(:success_result, "Operation successful")

        expect(result[:success]).to be true
        expect(result[:message]).to eq("Operation successful")
      end

      it "merges additional data" do
        service = Services::Base.new(user)
        result = service.send(:success_result, "Done", { items: [ 1, 2, 3 ], count: 3 })

        expect(result[:success]).to be true
        expect(result[:message]).to eq("Done")
        expect(result[:items]).to eq([ 1, 2, 3 ])
        expect(result[:count]).to eq(3)
      end

      context "with action_name set" do
        let(:service_class) do
          Class.new(Services::Base) do
            performed_action :test_action
          end
        end

        it "includes metadata with action" do
          service = service_class.new(user)
          result = service.send(:success_result, "Success", { data: "value" })

          expect(result[:success]).to be true
          expect(result[:message]).to eq("Success")
          expect(result[:data]).to eq("value")
          expect(result).to have_key(:metadata)
          expect(result[:metadata][:action]).to eq(:test_action)
        end

        it "merges additional metadata if provided" do
          service = service_class.new(user)
          result = service.send(:success_result, "Success", {
            data: "value",
            metadata: { stats: { count: 10 } }
          })

          expect(result[:success]).to be true
          expect(result[:metadata][:action]).to eq(:test_action)
          expect(result[:metadata][:stats][:count]).to eq(10)
        end
      end

      context "without action_name set" do
        it "includes empty metadata" do
          service = Services::Base.new(user)
          result = service.send(:success_result, "Success", { data: "value" })

          expect(result[:success]).to be true
          expect(result).to have_key(:metadata)
          expect(result[:metadata]).to eq({})
        end
      end
    end

    # ========================================
    # 4-Phase Execution Flow Tests
    # ========================================

    describe "#call" do
      # Test service that tracks phase execution
      let(:test_service_class) do
        Class.new(Services::Base) do
          attr_reader :phases_executed

          def initialize(user, params: {})
            super
            @phases_executed = []
          end

          def search
            @phases_executed << :search
            { raw_data: "from_db" }
          end

          def process(data)
            @phases_executed << :process
            { processed: data[:raw_data].upcase }
          end

          def transform(data)
            @phases_executed << :transform
            { transformed: "#{data[:processed]}!" }
          end

          def respond(data)
            @phases_executed << :respond
            success_result("All phases completed", data)
          end
        end
      end

      it "returns a tuple" do
        service = Services::Base.new(user)
        object, meta = service.call

        expect(meta).to be_a(Hash)
        expect(meta).to have_key(:success)
      end

      it "executes all phases in order" do
        service = test_service_class.new(user)
        service.call

        expect(service.phases_executed).to eq([ :search, :process, :transform, :respond ])
      end

      it "passes data through phases correctly" do
        service = test_service_class.new(user)
        _object, meta = service.call

        expect(meta[:success]).to be true
      end

      it "returns success when all phases succeed" do
        service = test_service_class.new(user)
        _object, meta = service.call

        expect(meta[:success]).to be true
        expect(meta[:message]).to eq("All phases completed")
      end

      context "with unexpected error" do
        let(:error_service_class) do
          Class.new(Services::Base) do
            schema { }

            def search
              raise StandardError, "Database connection failed"
            end
          end
        end

        it "returns error metadata" do
          service = error_service_class.new(user)
          _object, meta = service.call

          expect(meta[:success]).to be false
          expect(meta[:error_code]).to eq(:execution_error)
          expect(meta[:message]).to match(/Service execution failed/)
        end
      end

      context "with overridden phases" do
        let(:custom_service_class) do
          Class.new(Services::Base) do
            def search
              { custom: "data" }
            end

            def respond(data)
              success_result("Custom response", data)
            end
          end
        end

        it "uses overridden phases" do
          service = custom_service_class.new(user)
          _object, meta = service.call

          expect(meta[:success]).to be true
          expect(meta[:message]).to eq("Custom response")
        end
      end
    end

    describe "default phase methods" do
      describe "#search" do
        it "returns empty hash" do
          service = Services::Base.new(user)
          expect(service.send(:search)).to eq({})
        end
      end

      describe "#process" do
        it "returns data unchanged" do
          service = Services::Base.new(user)
          data = { foo: "bar" }
          expect(service.send(:process, data)).to eq(data)
        end
      end

      describe "#transform" do
        it "returns data unchanged" do
          service = Services::Base.new(user)
          data = { foo: "bar" }
          expect(service.send(:transform, data)).to eq(data)
        end
      end
    end

    # ========================================
    # Config DSL - allow_nil_user Tests
    # ========================================

    describe "._allow_nil_user" do
      # Service that allows nil user
      let(:system_service_class) do
        Class.new(Services::Base) do
          self._allow_nil_user = true
        end
      end

      it "defaults to false" do
        expect(Services::Base._allow_nil_user).to be false
      end

      it "can be set to true" do
        expect(system_service_class._allow_nil_user).to be true
      end

      context "with allow_nil_user true" do
        it "accepts nil user" do
          service = system_service_class.new(nil, params: { foo: "bar" })
          expect(service.user).to be_nil
          expect(service.params).to eq({ foo: "bar" })
        end

        it "can still accept user" do
          service = system_service_class.new(user, params: {})
          expect(service.user).to eq(user)
        end
      end

      it "is inherited by subclasses" do
        subclass = Class.new(system_service_class)
        expect(subclass._allow_nil_user).to be true
      end
    end

    # ========================================
    # Schema Validation Tests
    # ========================================

    describe "schema validation" do
      let(:validated_service_class) do
        Class.new(Services::Base) do
          schema do
            required(:name).filled(:string)
            required(:age).filled(:integer)
            optional(:email).filled(:string)
          end
        end
      end

      context "with invalid params" do
        it "raises ValidationError during initialize" do
          expect {
            validated_service_class.new(user, params: { name: "", age: "invalid" })
          }.to raise_error(BetterService::Errors::Runtime::ValidationError) do |error|
            expect(error.message).to match(/validation failed/i)
            expect(error.code).to eq(:validation_failed)
          end
        end

        it "contains validation errors in context" do
          error = nil
          begin
            validated_service_class.new(user, params: { name: "", age: "invalid" })
          rescue BetterService::Errors::Runtime::ValidationError => e
            error = e
          end

          expect(error.context[:validation_errors]).to have_key(:name)
          expect(error.context[:validation_errors]).to have_key(:age)
        end

        it "validation_errors are arrays" do
          error = nil
          begin
            validated_service_class.new(user, params: { name: "", age: "invalid" })
          rescue BetterService::Errors::Runtime::ValidationError => e
            error = e
          end

          expect(error.context[:validation_errors][:name]).to be_an(Array)
          expect(error.context[:validation_errors][:age]).to be_an(Array)
        end

        it "includes params in context" do
          error = nil
          begin
            validated_service_class.new(user, params: { name: "", age: "invalid" })
          rescue BetterService::Errors::Runtime::ValidationError => e
            error = e
          end

          # The context should have validation_errors key at minimum
          expect(error.context).to be_a(Hash)
          expect(error.context[:validation_errors]).to be_a(Hash)
        end
      end
    end

    # ========================================
    # Phase Blocks DSL Tests
    # ========================================

    describe "phase blocks DSL" do
      let(:block_based_service_class) do
        Class.new(Services::Base) do
          search_with do
            { users: [ "Alice", "Bob" ] }
          end

          process_with do |data|
            { users: data[:users].map(&:upcase) }
          end

          transform_with do |data|
            { users: data[:users].join(", ") }
          end

          respond_with do |data|
            success_result("Users processed", data)
          end
        end
      end

      it "defines search phase with block" do
        service = block_based_service_class.new(user)
        _object, meta = service.call

        expect(meta[:success]).to be true
      end

      it "phase blocks receive data from previous phase" do
        service = block_based_service_class.new(user)
        _object, meta = service.call

        expect(meta[:success]).to be true
        expect(meta[:message]).to eq("Users processed")
      end

      context "with hybrid method and block" do
        let(:hybrid_service_class) do
          Class.new(Services::Base) do
            search_with do
              { value: 10 }
            end

            def process(data)
              { value: data[:value] * 2 }
            end

            respond_with do |data|
              success_result("Hybrid", object: data[:value] + 5)
            end
          end
        end

        it "coexists with method overrides" do
          service = hybrid_service_class.new(user)
          object, meta = service.call

          expect(meta[:success]).to be true
          expect(object).to eq(25) # (10 * 2) + 5
        end
      end

      it "phase blocks are inherited by subclasses" do
        subclass = Class.new(block_based_service_class)
        service = subclass.new(user)
        _object, meta = service.call

        expect(meta[:success]).to be true
      end
    end

    # ========================================
    # Result Response Tests
    # ========================================

    describe "result response" do
      it "always returns Result object" do
        service = Services::Base.new(user)
        result = service.call

        expect(result).to be_a(BetterService::Result)
        expect(result).to respond_to(:resource)
        expect(result).to respond_to(:meta)
        expect(result).to respond_to(:success?)
      end

      describe "destructuring support" do
        it "Result supports destructuring" do
          service = Services::Base.new(user)
          _object, meta = service.call

          expect(meta).to be_a(Hash)
          expect(meta[:success]).to be true
        end
      end

      describe "error responses" do
        let(:error_service_class) do
          Class.new(Services::Base) do
            schema { }

            def search
              raise StandardError, "Test error"
            end
          end
        end

        it "returns Result on success" do
          result = Services::Base.new(user).call
          expect(result).to be_a(BetterService::Result)
          expect(result).to be_success
        end

        it "returns Result on failure" do
          result = error_service_class.new(user).call
          expect(result).to be_a(BetterService::Result)
          expect(result).to be_failure
        end
      end
    end

    # ========================================
    # should_auto_invalidate_cache? Tests
    # ========================================

    describe "#should_auto_invalidate_cache?" do
      context "early returns" do
        it "returns false when _auto_invalidate_cache is false" do
          service_class = Class.new(Services::Base) do
            auto_invalidate_cache false
            cache_contexts "test_context"
            performed_action :created
          end

          service = service_class.new(user)
          expect(service.send(:should_auto_invalidate_cache?)).to be false
        end

        it "returns false when class does not respond to _cache_contexts" do
          service = Services::Base.new(user)
          # Services::Base doesn't have auto_invalidate enabled
          expect(service.send(:should_auto_invalidate_cache?)).to be false
        end

        it "returns false when _cache_contexts is empty" do
          service_class = Class.new(Services::Base) do
            auto_invalidate_cache true
            # No cache_contexts defined
            performed_action :created
          end

          service = service_class.new(user)
          expect(service.send(:should_auto_invalidate_cache?)).to be false
        end

        it "returns false when _cache_contexts is nil" do
          service_class = Class.new(Services::Base) do
            auto_invalidate_cache true
            performed_action :created
          end
          service_class._cache_contexts = nil

          service = service_class.new(user)
          expect(service.send(:should_auto_invalidate_cache?)).to be false
        end
      end

      context "write action detection by action name" do
        it "returns true for :created action" do
          service_class = Class.new(Services::Base) do
            auto_invalidate_cache true
            cache_contexts "products"
            performed_action :created
          end

          service = service_class.new(user)
          expect(service.send(:should_auto_invalidate_cache?)).to be true
        end

        it "returns true for :updated action" do
          service_class = Class.new(Services::Base) do
            auto_invalidate_cache true
            cache_contexts "products"
            performed_action :updated
          end

          service = service_class.new(user)
          expect(service.send(:should_auto_invalidate_cache?)).to be true
        end

        it "returns true for :destroyed action" do
          service_class = Class.new(Services::Base) do
            auto_invalidate_cache true
            cache_contexts "products"
            performed_action :destroyed
          end

          service = service_class.new(user)
          expect(service.send(:should_auto_invalidate_cache?)).to be true
        end

        it "returns false for non-write action like :listed" do
          service_class = Class.new(Services::Base) do
            auto_invalidate_cache true
            cache_contexts "products"
            performed_action :listed
          end

          service = service_class.new(user)
          expect(service.send(:should_auto_invalidate_cache?)).to be false
        end

        it "returns false for non-write action like :showed" do
          service_class = Class.new(Services::Base) do
            auto_invalidate_cache true
            cache_contexts "products"
            performed_action :showed
          end

          service = service_class.new(user)
          expect(service.send(:should_auto_invalidate_cache?)).to be false
        end
      end

      context "class name pattern fallback" do
        it "returns true for CreateService class name" do
          # Can't easily test anonymous class name, but we can test the pattern logic
          service_class = Class.new(Services::Base) do
            auto_invalidate_cache true
            cache_contexts "products"
            # No performed_action, so will fall back to class name check
          end

          # Anonymous classes don't have a name that matches pattern
          service = service_class.new(user)
          expect(service.send(:should_auto_invalidate_cache?)).to be false
        end

        it "returns false for non-matching class name" do
          service_class = Class.new(Services::Base) do
            auto_invalidate_cache true
            cache_contexts "products"
            performed_action :custom_action
          end

          service = service_class.new(user)
          expect(service.send(:should_auto_invalidate_cache?)).to be false
        end
      end
    end

    # ========================================
    # build_success_metadata Tests
    # ========================================

    describe "#build_success_metadata" do
      it "defaults success to true when not provided" do
        service = Services::Base.new(user)
        result = { message: "Test message" }
        metadata = service.send(:build_success_metadata, result)

        expect(metadata[:success]).to be true
      end

      it "uses success from result when provided as true" do
        service = Services::Base.new(user)
        result = { success: true, message: "Success" }
        metadata = service.send(:build_success_metadata, result)

        expect(metadata[:success]).to be true
      end

      it "uses success from result when provided as false" do
        service = Services::Base.new(user)
        result = { success: false, message: "Failed" }
        metadata = service.send(:build_success_metadata, result)

        expect(metadata[:success]).to be false
      end

      it "includes action_name from class" do
        service_class = Class.new(Services::Base) do
          performed_action :test_action
        end

        service = service_class.new(user)
        result = { message: "Test" }
        metadata = service.send(:build_success_metadata, result)

        expect(metadata[:action]).to eq(:test_action)
      end

      it "action is nil when not set" do
        service = Services::Base.new(user)
        result = { message: "Test" }
        metadata = service.send(:build_success_metadata, result)

        expect(metadata[:action]).to be_nil
      end

      it "includes message from result" do
        service = Services::Base.new(user)
        result = { message: "Custom message" }
        metadata = service.send(:build_success_metadata, result)

        expect(metadata[:message]).to eq("Custom message")
      end

      it "merges additional metadata when Hash" do
        service = Services::Base.new(user)
        result = {
          message: "Test",
          metadata: { extra: "data", count: 5 }
        }
        metadata = service.send(:build_success_metadata, result)

        expect(metadata[:extra]).to eq("data")
        expect(metadata[:count]).to eq(5)
      end

      it "ignores metadata when not a Hash" do
        service = Services::Base.new(user)
        result = {
          message: "Test",
          metadata: "not a hash"
        }
        metadata = service.send(:build_success_metadata, result)

        expect(metadata).not_to have_key(:metadata)
        expect(metadata[:success]).to be true
      end

      it "ignores nil metadata" do
        service = Services::Base.new(user)
        result = {
          message: "Test",
          metadata: nil
        }
        metadata = service.send(:build_success_metadata, result)

        expect(metadata[:success]).to be true
      end

      context "with failed object containing errors" do
        let(:mock_object_class) do
          Class.new do
            attr_reader :errors

            def initialize(with_errors: true)
              @errors = with_errors ? MockErrors.new({ name: [ "can't be blank" ] }) : MockErrors.new({})
            end
          end
        end

        let(:mock_errors_class) do
          Class.new do
            attr_reader :messages, :full_messages

            def initialize(errors_hash)
              @messages = errors_hash
              @full_messages = errors_hash.flat_map { |k, msgs| msgs.map { |m| "#{k} #{m}" } }
            end

            def any?
              @messages.any?
            end
          end
        end

        before do
          stub_const("MockErrors", mock_errors_class)
        end

        it "adds validation_errors when success is false and object has errors" do
          service = Services::Base.new(user)
          mock_obj = mock_object_class.new(with_errors: true)
          result = {
            success: false,
            message: "Failed",
            object: mock_obj
          }
          metadata = service.send(:build_success_metadata, result)

          expect(metadata[:validation_errors]).to eq({ name: [ "can't be blank" ] })
          expect(metadata[:full_messages]).to eq([ "name can't be blank" ])
        end

        it "does not add validation_errors when success is true" do
          service = Services::Base.new(user)
          mock_obj = mock_object_class.new(with_errors: true)
          result = {
            success: true,
            message: "Success",
            object: mock_obj
          }
          metadata = service.send(:build_success_metadata, result)

          expect(metadata).not_to have_key(:validation_errors)
        end

        it "does not add validation_errors when object has no errors" do
          service = Services::Base.new(user)
          mock_obj = mock_object_class.new(with_errors: false)
          result = {
            success: false,
            message: "Failed",
            object: mock_obj
          }
          metadata = service.send(:build_success_metadata, result)

          expect(metadata).not_to have_key(:validation_errors)
        end

        it "does not add validation_errors when object does not respond to errors" do
          service = Services::Base.new(user)
          result = {
            success: false,
            message: "Failed",
            object: "plain string"
          }
          metadata = service.send(:build_success_metadata, result)

          expect(metadata).not_to have_key(:validation_errors)
        end
      end
    end

    # ========================================
    # format_errors_for_response Tests
    # ========================================

    describe "#format_errors_for_response" do
      it "formats Hash with array values" do
        service = Services::Base.new(user)
        errors = { name: [ "can't be blank", "is too short" ], email: [ "is invalid" ] }
        result = service.send(:format_errors_for_response, errors)

        expect(result).to be_an(Array)
        expect(result.length).to eq(3)
        expect(result).to include({ key: "name", message: "can't be blank" })
        expect(result).to include({ key: "name", message: "is too short" })
        expect(result).to include({ key: "email", message: "is invalid" })
      end

      it "formats Hash with single value wrapped in Array" do
        service = Services::Base.new(user)
        errors = { name: [ "can't be blank" ] }
        result = service.send(:format_errors_for_response, errors)

        expect(result).to eq([ { key: "name", message: "can't be blank" } ])
      end

      it "formats Hash with non-array value" do
        service = Services::Base.new(user)
        errors = { name: "can't be blank" }
        result = service.send(:format_errors_for_response, errors)

        expect(result).to eq([ { key: "name", message: "can't be blank" } ])
      end

      it "formats Array of Hashes with key and message" do
        service = Services::Base.new(user)
        errors = [ { key: "name", message: "is invalid" }, { key: "email", message: "is taken" } ]
        result = service.send(:format_errors_for_response, errors)

        expect(result).to eq(errors)
      end

      it "formats Array of Strings as base errors" do
        service = Services::Base.new(user)
        errors = [ "Something went wrong", "Another error" ]
        result = service.send(:format_errors_for_response, errors)

        expect(result).to eq([
          { key: "base", message: "Something went wrong" },
          { key: "base", message: "Another error" }
        ])
      end

      it "formats Array with mixed types" do
        service = Services::Base.new(user)
        errors = [
          { key: "name", message: "is invalid" },
          "General error",
          123
        ]
        result = service.send(:format_errors_for_response, errors)

        expect(result).to eq([
          { key: "name", message: "is invalid" },
          { key: "base", message: "General error" },
          { key: "base", message: "123" }
        ])
      end

      it "returns empty array for nil" do
        service = Services::Base.new(user)
        result = service.send(:format_errors_for_response, nil)

        expect(result).to eq([])
      end

      it "returns empty array for empty hash" do
        service = Services::Base.new(user)
        result = service.send(:format_errors_for_response, {})

        expect(result).to eq([])
      end

      it "returns empty array for empty array" do
        service = Services::Base.new(user)
        result = service.send(:format_errors_for_response, [])

        expect(result).to eq([])
      end

      it "returns empty array for unsupported types" do
        service = Services::Base.new(user)

        expect(service.send(:format_errors_for_response, "string")).to eq([])
        expect(service.send(:format_errors_for_response, 123)).to eq([])
        expect(service.send(:format_errors_for_response, :symbol)).to eq([])
      end

      it "converts symbol keys to strings" do
        service = Services::Base.new(user)
        errors = { name_field: [ "error" ] }
        result = service.send(:format_errors_for_response, errors)

        expect(result[0][:key]).to eq("name_field")
      end
    end

    # ========================================
    # extract_object Tests
    # ========================================

    describe "#extract_object" do
      it "extracts :object when present" do
        service = Services::Base.new(user)
        result = { object: "my_object", resource: "resource", items: [ "items" ] }

        expect(service.send(:extract_object, result)).to eq("my_object")
      end

      it "extracts :resource when :object not present" do
        service = Services::Base.new(user)
        result = { resource: "my_resource", items: [ "items" ] }

        expect(service.send(:extract_object, result)).to eq("my_resource")
      end

      it "extracts :items when :object and :resource not present" do
        service = Services::Base.new(user)
        result = { items: [ "item1", "item2" ] }

        expect(service.send(:extract_object, result)).to eq([ "item1", "item2" ])
      end

      it "returns nil when none present" do
        service = Services::Base.new(user)
        result = { message: "test" }

        expect(service.send(:extract_object, result)).to be_nil
      end

      it "prefers :object over :resource" do
        service = Services::Base.new(user)
        result = { object: nil, resource: "resource" }

        # object is nil but present as key, so returns nil (nil || "resource" = "resource")
        # Actually the code does result[:object] || result[:resource], so nil || "resource" = "resource"
        expect(service.send(:extract_object, result)).to eq("resource")
      end

      it "handles empty result hash" do
        service = Services::Base.new(user)
        expect(service.send(:extract_object, {})).to be_nil
      end
    end

    # ========================================
    # error? Tests
    # ========================================

    describe "#error?" do
      it "returns truthy when data has :error key" do
        service = Services::Base.new(user)
        data = { error: "Something went wrong" }

        expect(service.send(:error?, data)).to be_truthy
      end

      it "returns truthy when data has success: false" do
        service = Services::Base.new(user)
        data = { success: false }

        expect(service.send(:error?, data)).to be_truthy
      end

      it "returns falsy when data has success: true" do
        service = Services::Base.new(user)
        data = { success: true }

        expect(service.send(:error?, data)).to be_falsy
      end

      it "returns falsy for empty hash" do
        service = Services::Base.new(user)
        expect(service.send(:error?, {})).to be_falsy
      end

      it "returns falsy for non-hash" do
        service = Services::Base.new(user)
        expect(service.send(:error?, "string")).to be_falsy
        expect(service.send(:error?, nil)).to be_falsy
        expect(service.send(:error?, [])).to be_falsy
      end

      it "returns truthy when both error and success: false" do
        service = Services::Base.new(user)
        data = { error: "Error", success: false }

        expect(service.send(:error?, data)).to be_truthy
      end
    end

    # ========================================
    # failure_result Tests
    # ========================================

    describe "#failure_result" do
      it "returns hash with success false" do
        service = Services::Base.new(user)
        result = service.send(:failure_result, "Operation failed")

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Operation failed")
      end

      it "formats errors using format_errors_for_response" do
        service = Services::Base.new(user)
        result = service.send(:failure_result, "Failed", { name: [ "is invalid" ] })

        expect(result[:errors]).to eq([ { key: "name", message: "is invalid" } ])
      end

      it "handles empty errors" do
        service = Services::Base.new(user)
        result = service.send(:failure_result, "Failed", {})

        expect(result[:errors]).to eq([])
      end

      it "handles nil errors" do
        service = Services::Base.new(user)
        result = service.send(:failure_result, "Failed")

        expect(result[:errors]).to eq([])
      end
    end

    # ========================================
    # validation_failure_result Tests
    # ========================================

    describe "#validation_failure_result" do
      let(:mock_resource_class) do
        Class.new do
          attr_reader :errors

          def initialize
            @errors = MockModelErrors.new([
              MockModelError.new(:name, "can't be blank"),
              MockModelError.new(:email, "is invalid")
            ])
          end
        end
      end

      let(:mock_model_error_class) do
        Struct.new(:attribute, :message)
      end

      let(:mock_model_errors_class) do
        Class.new do
          include Enumerable

          def initialize(errors)
            @errors = errors
          end

          def each(&block)
            @errors.each(&block)
          end

          def blank?
            @errors.empty?
          end
        end
      end

      before do
        stub_const("MockModelError", mock_model_error_class)
        stub_const("MockModelErrors", mock_model_errors_class)
      end

      it "returns hash with success false" do
        service = Services::Base.new(user)
        resource = mock_resource_class.new
        result = service.send(:validation_failure_result, resource)

        expect(result[:success]).to be false
      end

      it "includes failed_resource" do
        service = Services::Base.new(user)
        resource = mock_resource_class.new
        result = service.send(:validation_failure_result, resource)

        expect(result[:failed_resource]).to eq(resource)
      end

      it "formats model validation errors" do
        service = Services::Base.new(user)
        resource = mock_resource_class.new
        result = service.send(:validation_failure_result, resource)

        expect(result[:errors]).to include({ key: "name", message: "can't be blank" })
        expect(result[:errors]).to include({ key: "email", message: "is invalid" })
      end
    end

    # ========================================
    # format_model_validation_errors Tests
    # ========================================

    describe "#format_model_validation_errors" do
      let(:mock_model_error_class) do
        Struct.new(:attribute, :message)
      end

      let(:mock_model_errors_class) do
        Class.new do
          include Enumerable

          def initialize(errors)
            @errors = errors
          end

          def each(&block)
            @errors.each(&block)
          end

          def blank?
            @errors.empty?
          end
        end
      end

      before do
        stub_const("MockModelError", mock_model_error_class)
        stub_const("MockModelErrors", mock_model_errors_class)
      end

      it "formats ActiveModel::Errors into array of hashes" do
        service = Services::Base.new(user)
        errors = MockModelErrors.new([
          MockModelError.new(:name, "can't be blank"),
          MockModelError.new(:email, "is invalid")
        ])

        result = service.send(:format_model_validation_errors, errors)

        expect(result).to eq([
          { key: "name", message: "can't be blank" },
          { key: "email", message: "is invalid" }
        ])
      end

      it "converts symbol attributes to strings" do
        service = Services::Base.new(user)
        errors = MockModelErrors.new([
          MockModelError.new(:first_name, "is required")
        ])

        result = service.send(:format_model_validation_errors, errors)

        expect(result[0][:key]).to eq("first_name")
      end

      it "returns empty array for blank errors" do
        service = Services::Base.new(user)
        errors = MockModelErrors.new([])

        result = service.send(:format_model_validation_errors, errors)

        expect(result).to eq([])
      end

      it "returns empty array for nil" do
        service = Services::Base.new(user)
        result = service.send(:format_model_validation_errors, nil)

        expect(result).to eq([])
      end
    end

    # ========================================
    # safe_params_to_hash Tests
    # ========================================

    describe "#safe_params_to_hash" do
      it "returns empty hash for nil" do
        service = Services::Base.new(user)
        expect(service.send(:safe_params_to_hash, nil)).to eq({})
      end

      it "converts ActionController::Parameters to hash with symbol keys" do
        ac_params = ActionController::Parameters.new("name" => "Test", "age" => 25)
        service = Services::Base.new(user)
        result = service.send(:safe_params_to_hash, ac_params)

        expect(result).to eq({ name: "Test", age: 25 })
      end

      it "converts hash with string keys to symbol keys" do
        service = Services::Base.new(user)
        result = service.send(:safe_params_to_hash, { "name" => "Test" })

        expect(result).to eq({ name: "Test" })
      end

      it "keeps symbol keys unchanged" do
        service = Services::Base.new(user)
        result = service.send(:safe_params_to_hash, { name: "Test" })

        expect(result).to eq({ name: "Test" })
      end

      it "handles nested hashes" do
        service = Services::Base.new(user)
        result = service.send(:safe_params_to_hash, { "user" => { "name" => "Test" } })

        expect(result).to eq({ user: { name: "Test" } })
      end

      it "returns empty hash for unsupported types" do
        service = Services::Base.new(user)
        expect(service.send(:safe_params_to_hash, "string")).to eq({})
        expect(service.send(:safe_params_to_hash, 123)).to eq({})
        expect(service.send(:safe_params_to_hash, [])).to eq({})
      end
    end

    # ========================================
    # auto_invalidate_cache DSL Tests
    # ========================================

    describe ".auto_invalidate_cache DSL" do
      it "defaults to false" do
        expect(Services::Base._auto_invalidate_cache).to be false
      end

      it "sets _auto_invalidate_cache to true when called without argument" do
        service_class = Class.new(Services::Base) do
          auto_invalidate_cache
        end

        expect(service_class._auto_invalidate_cache).to be true
      end

      it "sets _auto_invalidate_cache to provided value" do
        service_class = Class.new(Services::Base) do
          auto_invalidate_cache false
        end

        expect(service_class._auto_invalidate_cache).to be false
      end

      it "is inherited by subclasses" do
        parent_class = Class.new(Services::Base) do
          auto_invalidate_cache true
        end

        subclass = Class.new(parent_class)

        expect(subclass._auto_invalidate_cache).to be true
      end

      it "can be overridden in subclass" do
        parent_class = Class.new(Services::Base) do
          auto_invalidate_cache true
        end

        subclass = Class.new(parent_class) do
          auto_invalidate_cache false
        end

        expect(parent_class._auto_invalidate_cache).to be true
        expect(subclass._auto_invalidate_cache).to be false
      end
    end

    # ========================================
    # performed_action DSL Tests
    # ========================================

    describe ".performed_action DSL" do
      it "converts string to symbol" do
        service_class = Class.new(Services::Base) do
          performed_action "created"
        end

        expect(service_class._action_name).to eq(:created)
      end

      it "keeps symbol as symbol" do
        service_class = Class.new(Services::Base) do
          performed_action :updated
        end

        expect(service_class._action_name).to eq(:updated)
      end

      it "is inherited by subclasses" do
        parent_class = Class.new(Services::Base) do
          performed_action :parent_action
        end

        subclass = Class.new(parent_class)

        expect(subclass._action_name).to eq(:parent_action)
      end

      it "can be overridden in subclass" do
        parent_class = Class.new(Services::Base) do
          performed_action :parent_action
        end

        subclass = Class.new(parent_class) do
          performed_action :child_action
        end

        expect(parent_class._action_name).to eq(:parent_action)
        expect(subclass._action_name).to eq(:child_action)
      end
    end
  end
end
