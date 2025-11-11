# frozen_string_literal: true

require "test_helper"

class TransactionalTest < ActiveSupport::TestCase
  class TestModel < ActiveRecord::Base
    self.table_name = "test_models"
  end

  class TransactionalService < BetterService::Services::Base
    self._allow_nil_user = true
    with_transaction true

    schema do
      required(:name).filled(:string)
    end

    process_with do
      model = TestModel.create!(name: params[:name])
      { resource: model }
    end
  end

  class NonTransactionalService < BetterService::Services::Base
    self._allow_nil_user = true
    with_transaction false

    schema do
      required(:name).filled(:string)
    end

    process_with do
      model = TestModel.create!(name: params[:name])
      { resource: model }
    end
  end

  class FailingTransactionalService < BetterService::Services::Base
    self._allow_nil_user = true
    with_transaction true

    schema do
      required(:name).filled(:string)
    end

    process_with do
      TestModel.create!(name: params[:name])
      raise StandardError, "Intentional failure"
    end
  end

  setup do
    # Create test table
    ActiveRecord::Base.connection.create_table :test_models, force: true do |t|
      t.string :name
      t.timestamps
    end
  end

  teardown do
    # Drop test table
    ActiveRecord::Base.connection.drop_table :test_models, if_exists: true
  end

  test "with_transaction sets class attribute" do
    assert_equal true, TransactionalService._with_transaction
    assert_equal false, NonTransactionalService._with_transaction
  end

  test "process wraps in transaction when enabled" do
    initial_count = TestModel.count

    result = TransactionalService.new(nil, params: { name: "Test" }).call

    assert result[:success]
    assert_equal initial_count + 1, TestModel.count
    assert_equal "Test", result[:resource].name
  end

  test "process does not wrap in transaction when disabled" do
    initial_count = TestModel.count

    result = NonTransactionalService.new(nil, params: { name: "Test" }).call

    assert result[:success]
    assert_equal initial_count + 1, TestModel.count
  end

  test "transaction rolls back on exception" do
    initial_count = TestModel.count

    error = assert_raises(BetterService::Errors::Runtime::ExecutionError) do
      FailingTransactionalService.new(nil, params: { name: "Test" }).call
    end

    # Error should be raised with proper code
    assert_equal :execution_error, error.code
    # Database should be unchanged (transaction rolled back)
    assert_equal initial_count, TestModel.count
  end

  test "non-transactional service does not rollback on exception" do
    class FailingNonTransactionalService < BetterService::Services::Base
      self._allow_nil_user = true
      with_transaction false

      schema do
        required(:name).filled(:string)
      end

      process_with do
        TestModel.create!(name: params[:name])
        raise StandardError, "Intentional failure"
      end
    end

    initial_count = TestModel.count

    error = assert_raises(BetterService::Errors::Runtime::ExecutionError) do
      FailingNonTransactionalService.new(nil, params: { name: "Test" }).call
    end

    # Error should be raised with proper code
    assert_equal :execution_error, error.code
    # Record should still be created (no transaction, no rollback)
    assert_equal initial_count + 1, TestModel.count
  end

  test "return value is preserved with transaction" do
    result = TransactionalService.new(nil, params: { name: "Test" }).call

    assert result[:success]
    assert_instance_of TestModel, result[:resource]
    assert_equal "Test", result[:resource].name
  end

  test "child class can override parent transaction setting" do
    class ParentService < BetterService::Services::Base
      with_transaction true

      schema do
        required(:name).filled(:string)
      end
    end

    class ChildService < ParentService
      with_transaction false
    end

    assert_equal true, ParentService._with_transaction
    assert_equal false, ChildService._with_transaction
  end
end
