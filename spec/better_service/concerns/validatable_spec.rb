# frozen_string_literal: true

require "rails_helper"

module BetterService
  module Concerns
    RSpec.describe "Validatable concern" do
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

      let(:validated_service_class) do
        Class.new(Services::Base) do
          schema do
            required(:name).filled(:string)
            required(:age).filled(:integer)
            optional(:email).filled(:string)
          end
        end
      end

      let(:paged_service_class) do
        Class.new(Services::Base) do
          schema do
            required(:page).filled(:integer, gteq?: 1)
          end
        end
      end

      let(:email_service_class) do
        Class.new(Services::Base) do
          schema do
            required(:email).filled(:string, format?: /@/)
          end
        end
      end

      describe "schema definition" do
        it "defines _schema class attribute" do
          expect(validated_service_class._schema).not_to be_nil
          expect(validated_service_class._schema).to be_a(Dry::Schema::Params)
        end

        it "schema is inherited by subclasses" do
          subclass = Class.new(validated_service_class)
          expect(subclass._schema).not_to be_nil
        end

        it "Base has default empty schema" do
          expect(Services::Base._schema).not_to be_nil
          expect(Services::Base._schema).to be_a(Dry::Schema::Params)
        end
      end

      describe "validation execution" do
        it "raises ValidationError for invalid params during initialize" do
          expect {
            validated_service_class.new(user, params: { name: "", age: "not_number" })
          }.to raise_error(BetterService::Errors::Runtime::ValidationError) do |error|
            expect(error.context[:validation_errors]).to have_key(:name)
            expect(error.context[:validation_errors]).to have_key(:age)
          end
        end

        it "raises ValidationError when required field missing" do
          expect {
            validated_service_class.new(user, params: { age: 30 })
          }.to raise_error(BetterService::Errors::Runtime::ValidationError) do |error|
            expect(error.context[:validation_errors]).to have_key(:name)
          end
        end

        it "raises ValidationError for type mismatches" do
          expect {
            validated_service_class.new(user, params: { name: "John", age: "twenty" })
          }.to raise_error(BetterService::Errors::Runtime::ValidationError) do |error|
            expect(error.context[:validation_errors]).to have_key(:age)
          end
        end

        it "raises ValidationError when custom rules fail" do
          expect {
            paged_service_class.new(user, params: { page: 0 })
          }.to raise_error(BetterService::Errors::Runtime::ValidationError) do |error|
            expect(error.context[:validation_errors]).to have_key(:page)
          end
        end
      end

      describe "error formatting" do
        it "formats validation errors as arrays in exception context" do
          error = nil
          begin
            validated_service_class.new(user, params: { name: "", age: "bad" })
          rescue BetterService::Errors::Runtime::ValidationError => e
            error = e
          end

          error.context[:validation_errors].each_value do |messages|
            expect(messages).to be_an(Array)
          end
        end

        it "collects multiple errors for same field in array" do
          error = nil
          begin
            email_service_class.new(user, params: { email: "" })
          rescue BetterService::Errors::Runtime::ValidationError => e
            error = e
          end

          expect(error.context[:validation_errors][:email]).to be_an(Array)
        end

        it "validation errors have correct structure" do
          error = nil
          begin
            validated_service_class.new(user, params: { name: "" })
          rescue BetterService::Errors::Runtime::ValidationError => e
            error = e
          end

          errors = error.context[:validation_errors]
          expect(errors).to be_a(Hash)
          expect(errors[:name]).to be_an(Array)
          expect(errors[:name]).to all(be_a(String))
        end
      end

      describe "integration with call flow" do
        it "initialize raises ValidationError with correct code" do
          expect {
            validated_service_class.new(user, params: { name: "" })
          }.to raise_error(BetterService::Errors::Runtime::ValidationError) do |error|
            expect(error.code).to eq(:validation_failed)
            expect(error.context[:validation_errors]).to be_a(Hash)
            expect(error.context[:validation_errors]).to have_key(:name)
          end
        end

        it "search phase not executed when validation fails" do
          search_called = false

          service_class = Class.new(Services::Base) do
            schema do
              required(:id).filled(:string)
            end

            define_method(:search) do
              search_called = true
              raise "Should not be called"
            end
          end

          expect {
            service_class.new(user, params: {})
          }.to raise_error(BetterService::Errors::Runtime::ValidationError) do |error|
            expect(error.code).to eq(:validation_failed)
          end

          expect(search_called).to be false
        end

        it "validation happens before search phase" do
          executed_phases = []

          service_class = Class.new(Services::Base) do
            schema do
              required(:name).filled(:string)
            end

            search_with do
              executed_phases << :search
              {}
            end
          end

          service = service_class.new(user, params: { name: "John" })
          service.call

          expect(executed_phases).to include(:search)
        end

        it "validation errors included in exception context" do
          expect {
            validated_service_class.new(user, params: { name: "", age: "bad" })
          }.to raise_error(BetterService::Errors::Runtime::ValidationError) do |error|
            expect(error.context[:validation_errors]).to have_key(:name)
            expect(error.context[:validation_errors]).to have_key(:age)
          end
        end
      end
    end
  end
end
