# frozen_string_literal: true

require "rails_helper"

module BetterService
  module Concerns
    RSpec.describe "Presentable concern" do
      let(:dummy_user_class) do
        Class.new do
          attr_accessor :id, :name

          def initialize(id: 1, name: "Test User")
            @id = id
            @name = name
          end
        end
      end

      let(:dummy_presenter_class) do
        Class.new do
          attr_reader :object, :options

          def initialize(object, **options)
            @object = object
            @options = options
          end

          def name
            object[:name]&.upcase || "N/A"
          end
        end
      end

      let(:user) { dummy_user_class.new }

      let(:service_with_presenter_class) do
        presenter_class = dummy_presenter_class
        Class.new(Services::Base) do
          presenter presenter_class

          search_with do
            { items: [{ name: "Item 1" }, { name: "Item 2" }] }
          end
        end
      end

      let(:service_with_presenter_options_class) do
        presenter_class = dummy_presenter_class
        Class.new(Services::Base) do
          presenter presenter_class
          presenter_options { { currency: "USD" } }
        end
      end

      describe "presenter configuration" do
        it "presenter DSL sets _presenter_class" do
          presenter_class = dummy_presenter_class
          service_class = Class.new(Services::Base) do
            presenter presenter_class
          end

          expect(service_class._presenter_class).to eq(presenter_class)
        end

        it "presenter configuration inherited by subclasses" do
          subclass = Class.new(service_with_presenter_class)
          expect(subclass._presenter_class).to eq(dummy_presenter_class)
        end

        it "_presenter_class defaults to nil" do
          expect(Services::Base._presenter_class).to be_nil
        end

        it "presenter_options DSL stores options block" do
          service = service_with_presenter_options_class.new(user)
          options = service.send(:instance_eval, &service_with_presenter_options_class._presenter_options)

          expect(options[:currency]).to eq("USD")
        end
      end

      describe "collection presentation" do
        it "transform applies presenter to items collection" do
          service = service_with_presenter_class.new(user)
          data = { items: [{ name: "Item 1" }, { name: "Item 2" }] }

          result = service.send(:transform, data)

          expect(result[:items]).to all(be_a(dummy_presenter_class))
          expect(result[:items].count).to eq(2)
        end

        it "transform handles empty items array" do
          service = service_with_presenter_class.new(user)
          data = { items: [] }

          result = service.send(:transform, data)

          expect(result[:items]).to eq([])
        end

        it "presenter initialized with options for collection" do
          service = service_with_presenter_options_class.new(user)
          data = { items: [{ price: 100 }] }

          result = service.send(:transform, data)
          presenter = result[:items].first

          expect(presenter.options[:currency]).to eq("USD")
        end

        it "transform preserves additional data with items" do
          service = service_with_presenter_class.new(user)
          data = { items: [{ name: "Item" }], pagination: { page: 1 }, stats: { total: 10 } }

          result = service.send(:transform, data)

          expect(result[:items]).to all(be_a(dummy_presenter_class))
          expect(result[:pagination]).to eq({ page: 1 })
          expect(result[:stats]).to eq({ total: 10 })
        end

        it "transform handles nil items gracefully" do
          service = service_with_presenter_class.new(user)
          data = { items: [nil, { name: "Valid" }] }

          result = service.send(:transform, data)

          expect(result[:items].count).to eq(2)
          expect(result[:items]).to all(be_a(dummy_presenter_class))
        end
      end

      describe "single resource presentation" do
        it "transform applies presenter to single resource" do
          service = service_with_presenter_class.new(user)
          data = { resource: { name: "Resource 1" } }

          result = service.send(:transform, data)

          expect(result[:resource]).to be_a(dummy_presenter_class)
        end

        it "presenter initialized with options for resource" do
          service = service_with_presenter_options_class.new(user)
          data = { resource: { price: 100 } }

          result = service.send(:transform, data)

          expect(result[:resource].options[:currency]).to eq("USD")
        end

        it "transform preserves additional data with resource" do
          service = service_with_presenter_class.new(user)
          data = { resource: { name: "Item" }, metadata: { version: 1 } }

          result = service.send(:transform, data)

          expect(result[:resource]).to be_a(dummy_presenter_class)
          expect(result[:metadata]).to eq({ version: 1 })
        end

        it "transform handles nil resource" do
          service = service_with_presenter_class.new(user)
          data = { resource: nil }

          result = service.send(:transform, data)

          expect(result[:resource]).to be_a(dummy_presenter_class)
        end
      end

      describe "edge cases and integration" do
        it "transform returns data unchanged when no presenter" do
          service = Services::Base.new(user)
          data = { items: [{ name: "Item" }] }

          result = service.send(:transform, data)

          expect(result).to eq(data)
        end

        it "transform returns data unchanged when no items/resource keys" do
          service = service_with_presenter_class.new(user)
          data = { custom_data: [1, 2, 3] }

          result = service.send(:transform, data)

          expect(result).to eq(data)
        end

        it "custom transform_with block overrides automatic presentation" do
          presenter_class = dummy_presenter_class
          service_class = Class.new(Services::Base) do
            presenter presenter_class

            transform_with do |data|
              { custom: "transformed" }
            end
          end

          service = service_class.new(user)
          data = { items: [{ name: "Item" }] }
          result = service.send(:transform, data)

          expect(result).to eq({ custom: "transformed" })
        end

        it "presenter applied during full service call" do
          presenter_class = dummy_presenter_class
          service_class = Class.new(Services::Base) do
            presenter presenter_class

            search_with do
              { items: [{ name: "Item 1" }] }
            end

            process_with do |data|
              data
            end
          end

          items, meta = service_class.new(user).call

          expect(meta[:success]).to be true
          expect(items).to all(be_a(presenter_class))
        end

        it "transform handles presenter initialization errors" do
          service_class = Class.new(Services::Base) do
            presenter Class.new do
              def initialize(object, **options)
                raise ArgumentError, "Invalid object"
              end
            end

            search_with { { items: [{}] } }
          end

          _object, meta = service_class.new(user).call

          expect(meta[:success]).to be false
          expect(meta[:error_code]).to eq(:execution_error)
          expect(meta[:message]).to match(/wrong number of arguments|invalid object/i)
        end

        it "transform works with ActiveRecord-like objects" do
          ar_object = Struct.new(:id, :name).new(1, "Record")
          service = service_with_presenter_class.new(user)
          data = { items: [ar_object] }

          result = service.send(:transform, data)

          expect(result[:items]).to all(be_a(dummy_presenter_class))
        end

        it "presenter_options evaluated in service context" do
          presenter_class = dummy_presenter_class
          service_class = Class.new(Services::Base) do
            presenter presenter_class
            presenter_options { { user_id: user.id } }

            search_with { { items: [{ name: "Item" }] } }
          end

          items, _meta = service_class.new(user).call
          presenter = items.first

          expect(presenter.options[:user_id]).to eq(user.id)
        end
      end
    end
  end
end
