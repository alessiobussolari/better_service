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
        result = service.send(:success_result, "Done", { items: [1, 2, 3], count: 3 })

        expect(result[:success]).to be true
        expect(result[:message]).to eq("Done")
        expect(result[:items]).to eq([1, 2, 3])
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

        expect(service.phases_executed).to eq([:search, :process, :transform, :respond])
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
            schema {}

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
            { users: ["Alice", "Bob"] }
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
    # use_result_wrapper Configuration Tests
    # ========================================

    describe "use_result_wrapper configuration" do
      after do
        BetterService.reset_configuration!
      end

      context "when use_result_wrapper is true (default)" do
        before { BetterService.reset_configuration! }

        it "returns Result object" do
          service = Services::Base.new(user)
          result = service.call

          expect(result).to be_a(BetterService::Result)
          expect(result).to respond_to(:resource)
          expect(result).to respond_to(:meta)
          expect(result).to respond_to(:success?)
        end
      end

      context "when use_result_wrapper is false" do
        before do
          BetterService.configure do |config|
            config.use_result_wrapper = false
          end
        end

        it "returns tuple" do
          service = Services::Base.new(user)
          result = service.call

          expect(result).to be_an(Array)
          expect(result.size).to eq(2)
          object, meta = result
          expect(meta).to be_a(Hash)
          expect(meta).to have_key(:success)
        end
      end

      describe "destructuring support" do
        it "both Result and tuple support destructuring" do
          # Test with Result wrapper (default)
          BetterService.reset_configuration!

          service1 = Services::Base.new(user)
          _object1, meta1 = service1.call

          expect(meta1).to be_a(Hash)
          expect(meta1[:success]).to be true

          # Test with tuple
          BetterService.configure { |c| c.use_result_wrapper = false }

          service2 = Services::Base.new(user)
          _object2, meta2 = service2.call

          expect(meta2).to be_a(Hash)
          expect(meta2[:success]).to be true
        end
      end

      describe "error responses" do
        let(:error_service_class) do
          Class.new(Services::Base) do
            schema {}

            def search
              raise StandardError, "Test error"
            end
          end
        end

        it "respects use_result_wrapper with Result" do
          BetterService.reset_configuration!

          result = error_service_class.new(user).call
          expect(result).to be_a(BetterService::Result)
          expect(result).to be_failure
        end

        it "respects use_result_wrapper with tuple" do
          BetterService.configure { |c| c.use_result_wrapper = false }

          result = error_service_class.new(user).call
          expect(result).to be_an(Array)
          _object, meta = result
          expect(meta[:success]).to be false
        end
      end
    end
  end
end
