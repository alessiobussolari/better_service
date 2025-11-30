# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Transactional concern" do
  # Create/drop test table around tests
  before(:all) do
    ActiveRecord::Base.connection.create_table :test_models, force: true do |t|
      t.string :name
      t.timestamps
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.drop_table :test_models, if_exists: true
  end

  # Define test model class
  let(:test_model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"
    end
  end

  let(:transactional_service_class) do
    model_class = test_model_class
    Class.new(BetterService::Services::Base) do
      self._allow_nil_user = true
      with_transaction true

      schema do
        required(:name).filled(:string)
      end

      define_method(:model_class) { model_class }

      process_with do
        model = model_class.create!(name: params[:name])
        { object: model }
      end

      respond_with do |data|
        { object: data[:object], success: true }
      end
    end
  end

  let(:non_transactional_service_class) do
    model_class = test_model_class
    Class.new(BetterService::Services::Base) do
      self._allow_nil_user = true
      with_transaction false

      schema do
        required(:name).filled(:string)
      end

      define_method(:model_class) { model_class }

      process_with do
        model = model_class.create!(name: params[:name])
        { object: model }
      end

      respond_with do |data|
        { object: data[:object], success: true }
      end
    end
  end

  let(:failing_transactional_service_class) do
    model_class = test_model_class
    Class.new(BetterService::Services::Base) do
      self._allow_nil_user = true
      with_transaction true

      schema do
        required(:name).filled(:string)
      end

      define_method(:model_class) { model_class }

      process_with do
        model_class.create!(name: params[:name])
        raise StandardError, "Intentional failure"
      end
    end
  end

  before(:each) do
    test_model_class.delete_all
  end

  describe ".with_transaction" do
    it "sets _with_transaction to true" do
      expect(transactional_service_class._with_transaction).to be true
    end

    it "sets _with_transaction to false" do
      expect(non_transactional_service_class._with_transaction).to be false
    end
  end

  describe "transactional service" do
    it "wraps in transaction when enabled" do
      initial_count = test_model_class.count

      model, meta = transactional_service_class.new(nil, params: { name: "Test" }).call

      expect(meta[:success]).to be true
      expect(test_model_class.count).to eq(initial_count + 1)
      expect(model.name).to eq("Test")
    end

    it "preserves return value" do
      model, meta = transactional_service_class.new(nil, params: { name: "Test" }).call

      expect(meta[:success]).to be true
      expect(model).to be_a(test_model_class)
      expect(model.name).to eq("Test")
    end
  end

  describe "non-transactional service" do
    it "does not wrap in transaction" do
      initial_count = test_model_class.count

      _model, meta = non_transactional_service_class.new(nil, params: { name: "Test" }).call

      expect(meta[:success]).to be true
      expect(test_model_class.count).to eq(initial_count + 1)
    end
  end

  describe "transaction rollback" do
    it "rolls back on exception" do
      initial_count = test_model_class.count

      _model, meta = failing_transactional_service_class.new(nil, params: { name: "Test" }).call

      expect(meta[:success]).to be false
      expect(meta[:error_code]).to eq(:execution_error)
      expect(test_model_class.count).to eq(initial_count)
    end

    it "does not rollback for non-transactional service" do
      model_class = test_model_class
      failing_non_transactional_class = Class.new(BetterService::Services::Base) do
        self._allow_nil_user = true
        with_transaction false

        schema do
          required(:name).filled(:string)
        end

        define_method(:model_class) { model_class }

        process_with do
          model_class.create!(name: params[:name])
          raise StandardError, "Intentional failure"
        end
      end

      initial_count = test_model_class.count

      _model, meta = failing_non_transactional_class.new(nil, params: { name: "Test" }).call

      expect(meta[:success]).to be false
      expect(meta[:error_code]).to eq(:execution_error)
      expect(test_model_class.count).to eq(initial_count + 1)
    end
  end

  describe "inheritance" do
    it "child class can override parent transaction setting" do
      parent_class = Class.new(BetterService::Services::Base) do
        with_transaction true

        schema do
          required(:name).filled(:string)
        end
      end

      child_class = Class.new(parent_class) do
        with_transaction false
      end

      expect(parent_class._with_transaction).to be true
      expect(child_class._with_transaction).to be false
    end
  end
end
