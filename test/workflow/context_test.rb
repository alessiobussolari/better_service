# frozen_string_literal: true

require "test_helper"

class BetterService::Workflowable::ContextTest < ActiveSupport::TestCase
  class User
    attr_accessor :id, :name
    def initialize(id, name)
      @id = id
      @name = name
    end
  end

  setup do
    @user = User.new(1, "Test User")
    @context = BetterService::Workflowable::Context.new(@user, initial_data: "value")
  end

  test "initializes with user and initial data" do
    assert_equal @user, @context.user
    assert_equal "value", @context.initial_data
  end

  test "starts in success state" do
    assert @context.success?
    assert_not @context.failure?
  end

  test "can be marked as failed with message" do
    @context.fail!("Something went wrong")

    assert @context.failure?
    assert_not @context.success?
    assert_equal "Something went wrong", @context.errors[:message]
  end

  test "can be marked as failed with errors hash" do
    @context.fail!("Invalid data", field1: "is required", field2: "is invalid")

    assert @context.failure?
    assert_equal "Invalid data", @context.errors[:message]
    assert_equal "is required", @context.errors[:field1]
    assert_equal "is invalid", @context.errors[:field2]
  end

  test "can add data with add method" do
    @context.add(:order, { id: 123 })

    assert_equal({ id: 123 }, @context.get(:order))
  end

  test "can set data with method= syntax" do
    @context.order = { id: 456 }

    assert_equal({ id: 456 }, @context.order)
  end

  test "can get data with method syntax" do
    @context.add(:product, { name: "Widget" })

    assert_equal({ name: "Widget" }, @context.product)
  end

  test "raises NoMethodError for undefined methods" do
    assert_raises(NoMethodError) do
      @context.nonexistent_method
    end
  end

  test "to_h returns all data" do
    @context.order = { id: 1 }
    @context.product = { id: 2 }

    hash = @context.to_h

    assert_equal "value", hash[:initial_data]
    assert_equal({ id: 1 }, hash[:order])
    assert_equal({ id: 2 }, hash[:product])
  end

  test "can be marked as called" do
    assert_not @context.called?

    @context.called!

    assert @context.called?
  end

  test "inspect shows useful debug information" do
    @context.order = { id: 1 }
    inspection = @context.inspect

    assert_includes inspection, "BetterService::Workflowable::Context"
    assert_includes inspection, "success=true"
  end
end
