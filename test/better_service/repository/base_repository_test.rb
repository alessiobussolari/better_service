# frozen_string_literal: true

require "test_helper"

module BetterService
  module Repository
    class BaseRepositoryTest < ActiveSupport::TestCase
      # ========================================
      # Mock Classes
      # ========================================

      # Mock model with full ActiveRecord-like interface
      class MockModel
        extend ActiveModel::Naming

        class << self
          attr_accessor :last_method_called, :last_args

          def reset!
            @last_method_called = nil
            @last_args = nil
            @records = []
          end

          def records
            @records ||= []
          end

          def find(id)
            @last_method_called = :find
            @last_args = [id]
            records.find { |r| r.id == id } || raise(ActiveRecord::RecordNotFound)
          end

          def find_by(attrs)
            @last_method_called = :find_by
            @last_args = [attrs]
            records.find { |r| attrs.all? { |k, v| r.send(k) == v } }
          end

          def where(conditions)
            @last_method_called = :where
            @last_args = [conditions]
            MockRelation.new(records.select { |r| conditions.all? { |k, v| r.send(k) == v } })
          end

          def all
            @last_method_called = :all
            MockRelation.new(records)
          end

          def count
            @last_method_called = :count
            records.size
          end

          def exists?(conditions)
            @last_method_called = :exists?
            @last_args = [conditions]
            records.any? { |r| conditions.all? { |k, v| r.send(k) == v } }
          end

          def new(attrs = {})
            instance = allocate
            instance.instance_variable_set(:@attributes, attrs)
            instance.instance_variable_set(:@errors, ActiveModel::Errors.new(instance))
            attrs.each { |k, v| instance.instance_variable_set("@#{k}", v) }
            instance
          end

          def create(attrs = {})
            instance = new(attrs)
            instance.instance_variable_set(:@id, records.size + 1)
            instance.instance_variable_set(:@persisted, true)
            records << instance
            instance
          end

          def create!(attrs = {})
            if attrs[:name].nil? || attrs[:name].to_s.empty?
              instance = new(attrs)
              instance.errors.add(:name, "can't be blank")
              raise ActiveRecord::RecordInvalid.new(instance)
            end
            create(attrs)
          end

          def human_attribute_name(attr, _options = {})
            attr.to_s.humanize
          end

          def lookup_ancestors
            [self]
          end

          def i18n_scope
            :activerecord
          end

          def search(predicates)
            @last_method_called = :search
            @last_args = [predicates]
            MockRelation.new(records)
          end
        end

        attr_accessor :id, :name, :status

        def initialize(attrs = {})
          @attributes = attrs
          @errors = ActiveModel::Errors.new(self)
          attrs.each { |k, v| instance_variable_set("@#{k}", v) }
        end

        def errors
          @errors
        end

        def update!(attrs)
          attrs.each { |k, v| instance_variable_set("@#{k}", v) }
          self
        end

        def destroy!
          self.class.records.delete(self)
          self
        end

        def persisted?
          @persisted || false
        end
      end

      # Mock ActiveRecord::Relation
      class MockRelation
        include Enumerable

        def initialize(records = [])
          @records = records
          @includes = []
          @joins = []
          @order = nil
          @offset = nil
          @limit = nil
        end

        def each(&block)
          to_a.each(&block)
        end

        def to_a
          result = @records
          result = result.drop(@offset) if @offset
          result = result.take(@limit) if @limit
          result
        end

        def first
          to_a.first
        end

        def includes(*args)
          @includes = args
          self
        end

        def joins(*args)
          @joins = args
          self
        end

        def order(clause)
          @order = clause
          self
        end

        def offset(value)
          @offset = value
          self
        end

        def limit(value)
          @limit = value
          self
        end

        def size
          to_a.size
        end

        def respond_to?(method, include_private = false)
          [:includes, :joins, :order, :offset, :limit, :first, :to_a].include?(method) || super
        end
      end

      # Repository with explicit model
      class ExplicitRepository < BaseRepository
        def initialize
          super(MockModel)
        end
      end

      # Repository that derives model name (will fail - no MockModel at top level)
      class InvalidRepository < BaseRepository
      end

      def setup
        MockModel.reset!
        # Pre-populate some records
        MockModel.create(name: "Product 1", status: "active")
        MockModel.create(name: "Product 2", status: "inactive")
        MockModel.create(name: "Product 3", status: "active")
        @repo = ExplicitRepository.new
      end

      # ========================================
      # Test Group 1: Initialization
      # ========================================

      test "initializes with explicit model class" do
        repo = ExplicitRepository.new
        assert_equal MockModel, repo.model
      end

      test "raises error when model class cannot be derived" do
        error = assert_raises(BetterService::Errors::Configuration::ConfigurationError) do
          InvalidRepository.new
        end
        assert_match(/Could not derive model class/, error.message)
      end

      # ========================================
      # Test Group 2: Delegate Methods
      # ========================================

      test "find delegates to model" do
        record = MockModel.records.first
        result = @repo.find(record.id)

        assert_equal :find, MockModel.last_method_called
        assert_equal record, result
      end

      test "find raises RecordNotFound for missing id" do
        assert_raises(ActiveRecord::RecordNotFound) do
          @repo.find(999)
        end
      end

      test "find_by delegates to model" do
        @repo.find_by(status: "active")

        assert_equal :find_by, MockModel.last_method_called
        assert_equal [{ status: "active" }], MockModel.last_args
      end

      test "where delegates to model" do
        result = @repo.where(status: "active")

        assert_equal :where, MockModel.last_method_called
        assert_kind_of MockRelation, result
      end

      test "all delegates to model" do
        result = @repo.all

        assert_equal :all, MockModel.last_method_called
        assert_kind_of MockRelation, result
      end

      test "count delegates to model" do
        result = @repo.count

        assert_equal :count, MockModel.last_method_called
        assert_equal 3, result
      end

      test "exists? delegates to model" do
        result = @repo.exists?(status: "active")

        assert_equal :exists?, MockModel.last_method_called
        assert result
      end

      # ========================================
      # Test Group 3: CRUD Operations
      # ========================================

      test "build creates unsaved instance" do
        instance = @repo.build(name: "New Product")

        assert_kind_of MockModel, instance
        assert_equal "New Product", instance.name
        refute instance.persisted?
      end

      test "new is alias for build" do
        instance = @repo.new(name: "New Product")

        assert_kind_of MockModel, instance
        assert_equal "New Product", instance.name
      end

      test "create saves record" do
        initial_count = MockModel.records.size

        instance = @repo.create(name: "Created Product", status: "active")

        assert_kind_of MockModel, instance
        assert instance.persisted?
        assert_equal initial_count + 1, MockModel.records.size
      end

      test "create! raises on validation failure" do
        assert_raises(ActiveRecord::RecordInvalid) do
          @repo.create!(name: nil)
        end
      end

      test "create! succeeds with valid attributes" do
        instance = @repo.create!(name: "Valid Product", status: "active")

        assert_kind_of MockModel, instance
        assert instance.persisted?
      end

      test "update updates existing record by instance" do
        record = MockModel.records.first
        original_name = record.name

        @repo.update(record, name: "Updated Name")

        assert_equal "Updated Name", record.name
        refute_equal original_name, record.name
      end

      test "update updates existing record by id" do
        record = MockModel.records.first
        id = record.id

        @repo.update(id, name: "Updated By ID")

        assert_equal "Updated By ID", record.name
      end

      test "destroy destroys record by instance" do
        record = MockModel.records.first
        initial_count = MockModel.records.size

        @repo.destroy(record)

        assert_equal initial_count - 1, MockModel.records.size
        refute_includes MockModel.records, record
      end

      test "destroy destroys record by id" do
        record = MockModel.records.first
        id = record.id
        initial_count = MockModel.records.size

        @repo.destroy(id)

        assert_equal initial_count - 1, MockModel.records.size
      end

      test "delete removes record without callbacks" do
        # Store original where method
        original_where = MockModel.method(:where)

        # For this test, we need to mock the where().delete_all chain
        MockModel.define_singleton_method(:where) do |conditions|
          @last_method_called = :where
          mock_relation = Class.new do
            def delete_all
              1
            end
          end.new
          mock_relation
        end

        result = @repo.delete(1)

        assert_equal 1, result

        # Restore original where method
        MockModel.define_singleton_method(:where, original_where)
      end

      # ========================================
      # Test Group 4: Search Method
      # ========================================

      test "search returns all records with empty predicates" do
        result = @repo.search({})

        assert_kind_of MockRelation, result
      end

      test "search applies predicates when model responds to search" do
        @repo.search({ status_eq: "active" })

        assert_equal :search, MockModel.last_method_called
        assert_equal [{ status_eq: "active" }], MockModel.last_args
      end

      test "search applies pagination by default" do
        result = @repo.search({})

        # Default pagination: page 1, per_page 20
        assert_respond_to result, :to_a
      end

      test "search with custom page and per_page" do
        result = @repo.search({}, page: 2, per_page: 1)

        # With 3 records, page 2 with per_page 1 should return 1 record (offset 1)
        assert_respond_to result, :to_a
      end

      test "search with limit 1 returns single record" do
        result = @repo.search({}, limit: 1)

        # Should return first record, not a relation
        assert_kind_of MockModel, result
      end

      test "search with integer limit limits results" do
        result = @repo.search({}, limit: 2)

        assert_respond_to result, :to_a
      end

      test "search with nil limit returns all without pagination" do
        result = @repo.search({}, limit: nil)

        assert_respond_to result, :to_a
      end

      test "search applies includes for eager loading" do
        result = @repo.search({}, includes: [:category, :user])

        assert_respond_to result, :to_a
      end

      test "search applies joins" do
        result = @repo.search({}, joins: [:category])

        assert_respond_to result, :to_a
      end

      test "search applies order" do
        result = @repo.search({}, order: "created_at DESC")

        assert_respond_to result, :to_a
      end

      # ========================================
      # Test Group 5: Edge Cases
      # ========================================

      test "search handles nil predicates" do
        result = @repo.search(nil)

        assert_respond_to result, :to_a
      end

      test "search compacts predicates removing nil values" do
        result = @repo.search({ status: "active", name: nil })

        assert_respond_to result, :to_a
      end

      test "resolve_record returns record if already a model instance" do
        record = MockModel.records.first
        resolved = @repo.send(:resolve_record, record)

        assert_equal record, resolved
      end

      test "resolve_record finds record by id" do
        record = MockModel.records.first
        resolved = @repo.send(:resolve_record, record.id)

        assert_equal record, resolved
      end
    end
  end
end
