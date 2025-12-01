# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterService::Result do
  # Dummy resource class for testing
  let(:dummy_resource_class) do
    Class.new do
      attr_accessor :id, :name, :errors

      def initialize(id: 1, name: "Test")
        @id = id
        @name = name
        @errors = ActiveModel::Errors.new(self)
      end
    end
  end

  let(:resource) { dummy_resource_class.new }

  describe "#initialize" do
    context "with resource and default meta" do
      subject(:result) { described_class.new(resource) }

      it "sets the resource" do
        expect(result.resource).to eq(resource)
      end

      it "defaults success to true" do
        expect(result.meta[:success]).to be true
      end
    end

    context "with custom meta" do
      subject(:result) { described_class.new(resource, meta: { success: false, message: "Failed" }) }

      it "sets the resource" do
        expect(result.resource).to eq(resource)
      end

      it "uses provided success value" do
        expect(result.meta[:success]).to be false
      end

      it "uses provided message" do
        expect(result.meta[:message]).to eq("Failed")
      end
    end

    context "with meta containing only message" do
      subject(:result) { described_class.new(nil, meta: { message: "Test" }) }

      it "defaults success to true" do
        expect(result.meta[:success]).to be true
      end

      it "preserves the message" do
        expect(result.meta[:message]).to eq("Test")
      end
    end

    context "with non-hash meta" do
      subject(:result) { described_class.new(nil, meta: "invalid") }

      it "defaults to success true hash" do
        expect(result.meta).to eq({ success: true })
      end
    end

    context "with multiple meta keys" do
      subject(:result) { described_class.new(nil, meta: { action: :created, message: "Done", extra: "data" }) }

      it "defaults success to true" do
        expect(result.meta[:success]).to be true
      end

      it "preserves action" do
        expect(result.meta[:action]).to eq(:created)
      end

      it "preserves message" do
        expect(result.meta[:message]).to eq("Done")
      end

      it "preserves extra data" do
        expect(result.meta[:extra]).to eq("data")
      end
    end
  end

  describe "#success?" do
    context "when success is true" do
      subject(:result) { described_class.new(nil, meta: { success: true }) }

      it { is_expected.to be_success }
      it { is_expected.not_to be_failure }
    end

    context "when success is false" do
      subject(:result) { described_class.new(nil, meta: { success: false }) }

      it { is_expected.not_to be_success }
      it { is_expected.to be_failure }
    end

    context "when success is not explicitly set" do
      subject(:result) { described_class.new(nil, meta: {}) }

      it "defaults to success" do
        expect(result).to be_success
      end
    end
  end

  describe "#failure?" do
    context "when success is false" do
      subject(:result) { described_class.new(nil, meta: { success: false }) }

      it { is_expected.to be_failure }
      it { is_expected.not_to be_success }
    end
  end

  describe "#message" do
    context "when message is set" do
      subject(:result) { described_class.new(nil, meta: { message: "Hello" }) }

      it "returns the message" do
        expect(result.message).to eq("Hello")
      end
    end

    context "when message is not set" do
      subject(:result) { described_class.new(nil) }

      it "returns nil" do
        expect(result.message).to be_nil
      end
    end
  end

  describe "#action" do
    context "when action is set" do
      subject(:result) { described_class.new(nil, meta: { action: :created }) }

      it "returns the action" do
        expect(result.action).to eq(:created)
      end
    end

    context "when action is not set" do
      subject(:result) { described_class.new(nil) }

      it "returns nil" do
        expect(result.action).to be_nil
      end
    end
  end

  describe "#validation_errors" do
    context "when validation_errors is set" do
      let(:errors) { { name: [ "can't be blank" ] } }
      subject(:result) { described_class.new(nil, meta: { validation_errors: errors }) }

      it "returns the validation errors" do
        expect(result.validation_errors).to eq(errors)
      end
    end

    context "when validation_errors is not set" do
      subject(:result) { described_class.new(nil) }

      it "returns nil" do
        expect(result.validation_errors).to be_nil
      end
    end
  end

  describe "#full_messages" do
    context "when full_messages is set" do
      let(:messages) { [ "Name can't be blank" ] }
      subject(:result) { described_class.new(nil, meta: { full_messages: messages }) }

      it "returns the full messages" do
        expect(result.full_messages).to eq(messages)
      end
    end

    context "when full_messages is not set" do
      subject(:result) { described_class.new(nil) }

      it "returns nil" do
        expect(result.full_messages).to be_nil
      end
    end
  end

  describe "#errors" do
    context "when resource has errors method" do
      subject(:result) { described_class.new(resource) }

      it "returns the resource errors" do
        expect(result.errors).to be_an_instance_of(ActiveModel::Errors)
      end
    end

    context "when resource is nil" do
      subject(:result) { described_class.new(nil) }

      it "returns nil" do
        expect(result.errors).to be_nil
      end
    end

    context "when resource has no errors method" do
      subject(:result) { described_class.new("plain string") }

      it "returns nil" do
        expect(result.errors).to be_nil
      end
    end
  end

  describe "#to_ary" do
    subject(:result) { described_class.new(resource, meta: { success: true, action: :created }) }

    it "enables destructuring" do
      obj, meta = result

      expect(obj).to eq(resource)
      expect(meta[:success]).to be true
      expect(meta[:action]).to eq(:created)
    end
  end

  describe "#deconstruct" do
    subject(:result) { described_class.new(nil) }

    it "is alias for to_ary" do
      expect(result.deconstruct).to eq(result.to_ary)
    end
  end

  describe "destructuring" do
    context "in method returns" do
      subject(:result) { described_class.new(resource, meta: { success: true }) }

      it "works correctly" do
        obj, meta = result

        expect(obj).to eq(resource)
        expect(meta[:success]).to be true
      end
    end

    context "with all meta keys" do
      subject(:result) do
        described_class.new(nil, meta: {
          success: false,
          action: :failed,
          message: "Error",
          validation_errors: { name: [ "blank" ] }
        })
      end

      it "preserves all meta keys" do
        _, meta = result

        expect(meta[:success]).to be false
        expect(meta[:action]).to eq(:failed)
        expect(meta[:message]).to eq("Error")
        expect(meta[:validation_errors]).to eq({ name: [ "blank" ] })
      end
    end
  end

  describe "#to_h" do
    context "with resource and meta" do
      subject(:result) { described_class.new(resource, meta: { success: true, message: "Test" }) }

      it "returns hash with resource" do
        expect(result.to_h[:resource]).to eq(resource)
      end

      it "returns hash with success meta" do
        expect(result.to_h[:meta][:success]).to be true
      end

      it "returns hash with message meta" do
        expect(result.to_h[:meta][:message]).to eq("Test")
      end
    end

    context "with nil resource" do
      subject(:result) { described_class.new(nil, meta: { success: false }) }

      it "returns nil resource" do
        expect(result.to_h[:resource]).to be_nil
      end

      it "returns failure meta" do
        expect(result.to_h[:meta][:success]).to be false
      end
    end
  end

  describe "real-world usage patterns" do
    context "successful service pattern" do
      subject(:result) do
        described_class.new(
          dummy_resource_class.new(id: 42, name: "Product"),
          meta: {
            success: true,
            action: :created,
            message: "Product created successfully"
          }
        )
      end

      it { is_expected.to be_success }

      it "returns resource with correct id" do
        expect(result.resource.id).to eq(42)
      end

      it "returns correct message" do
        expect(result.message).to eq("Product created successfully")
      end

      it "returns correct action" do
        expect(result.action).to eq(:created)
      end
    end

    context "failed service pattern" do
      let(:failed_resource) do
        res = dummy_resource_class.new
        res.errors.add(:name, "can't be blank")
        res
      end

      subject(:result) do
        described_class.new(
          failed_resource,
          meta: {
            success: false,
            action: :created,
            message: "Validation failed",
            validation_errors: { name: [ "can't be blank" ] },
            full_messages: [ "Name can't be blank" ]
          }
        )
      end

      it { is_expected.to be_failure }

      it "returns resource with errors" do
        expect(result.resource.errors).to be_any
      end

      it "returns validation errors" do
        expect(result.validation_errors).to eq({ name: [ "can't be blank" ] })
      end

      it "returns full messages" do
        expect(result.full_messages).to eq([ "Name can't be blank" ])
      end
    end

    context "array resource (index service)" do
      let(:resources) do
        [ dummy_resource_class.new(id: 1), dummy_resource_class.new(id: 2) ]
      end

      subject(:result) do
        described_class.new(
          resources,
          meta: {
            success: true,
            action: :listed,
            message: "Records retrieved"
          }
        )
      end

      it { is_expected.to be_success }

      it "returns array resource" do
        expect(result.resource).to be_an(Array)
      end

      it "returns correct count" do
        expect(result.resource.size).to eq(2)
      end

      it "returns correct action" do
        expect(result.action).to eq(:listed)
      end
    end

    context "controller pattern with success" do
      subject(:result) { described_class.new(resource, meta: { success: true }) }

      it "allows success branching" do
        branched = if result.success?
          :success
        else
          :failure
        end

        expect(branched).to eq(:success)
      end
    end

    context "controller pattern with failure using destructuring" do
      subject(:result) { described_class.new(resource, meta: { success: false, message: "Failed" }) }

      it "allows failure branching with destructuring" do
        product, meta = result

        branched = if meta[:success]
          :success
        else
          :failure
        end

        expect(branched).to eq(:failure)
        expect(product).to eq(resource)
        expect(meta[:message]).to eq("Failed")
      end
    end
  end

  describe "Hash-like interface" do
    let(:result_with_meta) do
      described_class.new(
        resource,
        meta: { action: :created, message: "Created successfully", extra_data: { count: 5 } }
      )
    end

    describe "#[]" do
      it "accesses :resource" do
        expect(result_with_meta[:resource]).to eq(resource)
      end

      it "accesses :meta" do
        expect(result_with_meta[:meta]).to be_a(Hash)
        expect(result_with_meta[:meta][:action]).to eq(:created)
      end

      it "accesses :success" do
        expect(result_with_meta[:success]).to be true
      end

      it "accesses :message" do
        expect(result_with_meta[:message]).to eq("Created successfully")
      end

      it "accesses :action from meta" do
        expect(result_with_meta[:action]).to eq(:created)
      end

      it "accesses arbitrary meta keys" do
        result = described_class.new(nil, meta: { custom_key: "custom_value" })
        expect(result[:custom_key]).to eq("custom_value")
      end

      it "returns nil for unknown keys" do
        expect(result_with_meta[:nonexistent]).to be_nil
      end
    end

    describe "#dig" do
      it "digs into top-level keys" do
        expect(result_with_meta.dig(:resource)).to eq(resource)
      end

      it "digs into meta" do
        expect(result_with_meta.dig(:meta, :action)).to eq(:created)
      end

      it "digs into nested meta data" do
        expect(result_with_meta.dig(:extra_data, :count)).to eq(5)
      end

      it "returns nil for empty keys" do
        expect(result_with_meta.dig).to be_nil
      end

      it "returns nil for missing keys" do
        expect(result_with_meta.dig(:nonexistent)).to be_nil
      end

      it "returns nil for deep missing keys" do
        expect(result_with_meta.dig(:extra_data, :nonexistent)).to be_nil
      end

      it "returns nil when intermediate is not diggable" do
        expect(result_with_meta.dig(:success, :something)).to be_nil
      end
    end

    describe "#key?" do
      it "returns true for :resource" do
        expect(result_with_meta.key?(:resource)).to be true
      end

      it "returns true for :meta" do
        expect(result_with_meta.key?(:meta)).to be true
      end

      it "returns true for :success" do
        expect(result_with_meta.key?(:success)).to be true
      end

      it "returns true for :message" do
        expect(result_with_meta.key?(:message)).to be true
      end

      it "returns true for :action" do
        expect(result_with_meta.key?(:action)).to be true
      end

      it "returns true for meta keys that exist" do
        result = described_class.new(nil, meta: { custom_key: "value" })
        expect(result.key?(:custom_key)).to be true
      end

      it "returns false for unknown keys" do
        expect(result_with_meta.key?(:unknown)).to be false
      end
    end

    describe "#has_key?" do
      it "is an alias for key?" do
        expect(result_with_meta.has_key?(:resource)).to be true
        expect(result_with_meta.has_key?(:unknown)).to be false
      end
    end

    describe "accessing nested meta via bracket and dig" do
      it "works with safe navigation dig pattern" do
        result = described_class.new(nil, meta: { validation_errors: { name: [ "can't be blank" ] } })
        errors = result&.dig(:validation_errors)

        expect(errors).to eq({ name: [ "can't be blank" ] })
      end

      it "works when meta key is nil" do
        result = described_class.new(nil, meta: {})
        errors = result&.dig(:validation_errors)

        expect(errors).to be_nil
      end

      it "works with bracket access after dig" do
        result = described_class.new(nil, meta: { validation_errors: { name: [ "can't be blank" ] } })

        if result&.dig(:validation_errors)
          name_errors = result[:validation_errors][:name]
          expect(name_errors).to eq([ "can't be blank" ])
        end
      end
    end
  end
end
