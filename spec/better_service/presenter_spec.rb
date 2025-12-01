# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterService::Presenter do
  # Object that responds to as_json
  let(:json_object) do
    Struct.new(:id, :name) do
      def as_json(opts = {})
        { id: id, name: name }
      end
    end.new(1, "Test Product")
  end

  # Object without as_json - create class that explicitly removes it
  let(:plain_object) do
    Class.new do
      undef_method :as_json if method_defined?(:as_json)

      attr_reader :value

      def initialize(value)
        @value = value
      end

      def to_s
        @value.to_s
      end

      def inspect
        "#<PlainObject: #{@value}>"
      end
    end.new("plain value")
  end

  # User with has_role? method
  let(:user_with_role) do
    Class.new do
      def has_role?(role)
        role.to_sym == :admin
      end
    end.new
  end

  # User without has_role? method
  let(:user_without_role) do
    Struct.new(:name).new("Regular User")
  end

  describe "#initialize" do
    it "stores the object" do
      presenter = described_class.new(json_object)
      expect(presenter.object).to eq(json_object)
    end

    it "stores options" do
      presenter = described_class.new(json_object, current_user: "user", extra: "value")
      expect(presenter.options).to eq({ current_user: "user", extra: "value" })
    end

    it "defaults options to empty hash" do
      presenter = described_class.new(json_object)
      expect(presenter.options).to eq({})
    end
  end

  describe "#as_json" do
    context "when object responds to as_json" do
      it "delegates to object" do
        presenter = described_class.new(json_object)
        expect(presenter.as_json).to eq({ id: 1, name: "Test Product" })
      end

      it "passes options to object.as_json" do
        custom_object = Class.new do
          def as_json(opts = {})
            { only: opts[:only] }
          end
        end.new

        presenter = described_class.new(custom_object)
        result = presenter.as_json(only: [ :id ])
        expect(result).to eq({ only: [ :id ] })
      end
    end

    context "when object does not respond to as_json" do
      it "wraps in data key" do
        presenter = described_class.new(plain_object)
        expect(presenter.as_json).to eq({ data: plain_object })
      end
    end

    context "with numeric object (Active Support adds as_json)" do
      it "delegates to object's as_json" do
        presenter = described_class.new(42)
        # In Rails, integers respond to as_json via Active Support
        expect(presenter.as_json).to eq(42)
      end
    end

    context "with array object" do
      it "delegates to array's as_json" do
        presenter = described_class.new([ 1, 2, 3 ])
        expect(presenter.as_json).to eq([ 1, 2, 3 ])
      end
    end
  end

  describe "#to_json" do
    it "returns valid JSON string" do
      presenter = described_class.new(json_object)
      json = presenter.to_json
      expect(JSON.parse(json)).to eq({ "id" => 1, "name" => "Test Product" })
    end

    it "passes options to as_json" do
      presenter = described_class.new(json_object)
      # to_json should produce valid JSON regardless of options
      expect { JSON.parse(presenter.to_json) }.not_to raise_error
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      presenter = described_class.new(json_object)
      expect(presenter.to_h).to eq({ id: 1, name: "Test Product" })
    end

    it "returns same result as as_json" do
      presenter = described_class.new(json_object)
      expect(presenter.to_h).to eq(presenter.as_json)
    end
  end

  describe "private method #current_user" do
    # Test via a subclass that exposes the private method
    let(:presenter_class) do
      Class.new(described_class) do
        def exposed_current_user
          current_user
        end
      end
    end

    it "returns user from options" do
      presenter = presenter_class.new(json_object, current_user: user_with_role)
      expect(presenter.exposed_current_user).to eq(user_with_role)
    end

    it "returns nil when not provided" do
      presenter = presenter_class.new(json_object)
      expect(presenter.exposed_current_user).to be_nil
    end
  end

  describe "private method #include_field?" do
    let(:presenter_class) do
      Class.new(described_class) do
        def exposed_include_field?(field)
          include_field?(field)
        end
      end
    end

    context "without fields option" do
      it "returns true for any field" do
        presenter = presenter_class.new(json_object)
        expect(presenter.exposed_include_field?(:any_field)).to be true
        expect(presenter.exposed_include_field?(:another)).to be true
      end
    end

    context "with fields option" do
      it "returns true for included fields (symbol)" do
        presenter = presenter_class.new(json_object, fields: [ :name, :email ])
        expect(presenter.exposed_include_field?(:name)).to be true
        expect(presenter.exposed_include_field?(:email)).to be true
      end

      it "returns true for included fields (string converted to symbol)" do
        presenter = presenter_class.new(json_object, fields: [ :name ])
        expect(presenter.exposed_include_field?("name")).to be true
      end

      it "returns false for excluded fields" do
        presenter = presenter_class.new(json_object, fields: [ :name ])
        expect(presenter.exposed_include_field?(:email)).to be false
        expect(presenter.exposed_include_field?(:price)).to be false
      end

      it "works with empty fields array" do
        presenter = presenter_class.new(json_object, fields: [])
        expect(presenter.exposed_include_field?(:name)).to be false
      end
    end
  end

  describe "private method #user_can?" do
    let(:presenter_class) do
      Class.new(described_class) do
        def exposed_user_can?(role)
          user_can?(role)
        end
      end
    end

    context "when current_user is nil" do
      it "returns false" do
        presenter = presenter_class.new(json_object)
        expect(presenter.exposed_user_can?(:admin)).to be false
      end
    end

    context "when user has has_role? method" do
      it "delegates to user.has_role? and returns true for matching role" do
        presenter = presenter_class.new(json_object, current_user: user_with_role)
        expect(presenter.exposed_user_can?(:admin)).to be true
      end

      it "returns false for non-matching role" do
        presenter = presenter_class.new(json_object, current_user: user_with_role)
        expect(presenter.exposed_user_can?(:moderator)).to be false
      end

      it "works with string role" do
        presenter = presenter_class.new(json_object, current_user: user_with_role)
        expect(presenter.exposed_user_can?("admin")).to be true
      end
    end

    context "when user lacks has_role? method" do
      it "returns false" do
        presenter = presenter_class.new(json_object, current_user: user_without_role)
        expect(presenter.exposed_user_can?(:admin)).to be false
      end
    end
  end

  describe "subclass usage" do
    let(:custom_presenter_class) do
      Class.new(described_class) do
        def as_json(opts = {})
          {
            id: object.id,
            display_name: object.name.upcase,
            formatted: true
          }
        end
      end
    end

    it "allows overriding as_json" do
      presenter = custom_presenter_class.new(json_object)
      result = presenter.as_json

      expect(result[:id]).to eq(1)
      expect(result[:display_name]).to eq("TEST PRODUCT")
      expect(result[:formatted]).to be true
    end

    it "to_json uses overridden as_json" do
      presenter = custom_presenter_class.new(json_object)
      parsed = JSON.parse(presenter.to_json)

      expect(parsed["display_name"]).to eq("TEST PRODUCT")
    end

    it "to_h uses overridden as_json" do
      presenter = custom_presenter_class.new(json_object)
      expect(presenter.to_h[:formatted]).to be true
    end
  end

  describe "integration with options" do
    let(:conditional_presenter_class) do
      Class.new(described_class) do
        def as_json(opts = {})
          result = { id: object.id, name: object.name }
          result[:admin_data] = "secret" if user_can?(:admin)
          result[:details] = "extra" if include_field?(:details)
          result
        end
      end
    end

    context "with admin user and details field requested" do
      it "includes admin_data and details" do
        presenter = conditional_presenter_class.new(
          json_object,
          current_user: user_with_role,
          fields: [ :id, :name, :details ]
        )

        result = presenter.as_json
        expect(result[:admin_data]).to eq("secret")
        expect(result[:details]).to eq("extra")
      end
    end

    context "with non-admin user" do
      it "excludes admin_data" do
        presenter = conditional_presenter_class.new(
          json_object,
          current_user: user_without_role
        )

        result = presenter.as_json
        expect(result).not_to have_key(:admin_data)
      end
    end

    context "without details field requested" do
      it "excludes details" do
        presenter = conditional_presenter_class.new(
          json_object,
          fields: [ :id, :name ]
        )

        result = presenter.as_json
        expect(result).not_to have_key(:details)
      end
    end
  end
end
