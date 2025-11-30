# frozen_string_literal: true

require "rails_helper"

module BetterService
  module Workflowable
    RSpec.describe Context do
      let(:dummy_user_class) do
        Class.new do
          attr_accessor :id, :name

          def initialize(id, name)
            @id = id
            @name = name
          end
        end
      end

      let(:user) { dummy_user_class.new(1, "Test User") }
      let(:context) { described_class.new(user, initial_data: "value") }

      describe "#initialize" do
        it "initializes with user and initial data" do
          expect(context.user).to eq(user)
          expect(context.initial_data).to eq("value")
        end
      end

      describe "#success?" do
        it "starts in success state" do
          expect(context).to be_success
          expect(context).not_to be_failure
        end
      end

      describe "#fail!" do
        it "can be marked as failed with message" do
          context.fail!("Something went wrong")

          expect(context).to be_failure
          expect(context).not_to be_success
          expect(context.errors[:message]).to eq("Something went wrong")
        end

        it "can be marked as failed with errors hash" do
          context.fail!("Invalid data", field1: "is required", field2: "is invalid")

          expect(context).to be_failure
          expect(context.errors[:message]).to eq("Invalid data")
          expect(context.errors[:field1]).to eq("is required")
          expect(context.errors[:field2]).to eq("is invalid")
        end
      end

      describe "#add and #get" do
        it "can add data with add method" do
          context.add(:order, { id: 123 })

          expect(context.get(:order)).to eq({ id: 123 })
        end
      end

      describe "dynamic attribute access" do
        it "can set data with method= syntax" do
          context.order = { id: 456 }

          expect(context.order).to eq({ id: 456 })
        end

        it "can get data with method syntax" do
          context.add(:product, { name: "Widget" })

          expect(context.product).to eq({ name: "Widget" })
        end

        it "raises NoMethodError for undefined methods" do
          expect {
            context.nonexistent_method
          }.to raise_error(NoMethodError)
        end
      end

      describe "#to_h" do
        it "returns all data" do
          context.order = { id: 1 }
          context.product = { id: 2 }

          hash = context.to_h

          expect(hash[:initial_data]).to eq("value")
          expect(hash[:order]).to eq({ id: 1 })
          expect(hash[:product]).to eq({ id: 2 })
        end
      end

      describe "#called!" do
        it "can be marked as called" do
          expect(context).not_to be_called

          context.called!

          expect(context).to be_called
        end
      end

      describe "#inspect" do
        it "shows useful debug information" do
          context.order = { id: 1 }
          inspection = context.inspect

          expect(inspection).to include("BetterService::Workflowable::Context")
          expect(inspection).to include("success=true")
        end
      end
    end
  end
end
