# frozen_string_literal: true

module BetterService
  module Repository
    # BaseRepository - Generic repository pattern for data access
    #
    # Provides a clean abstraction layer between services and ActiveRecord models.
    # Repositories handle all database queries using predicates-based search,
    # enforcing separation of concerns and enabling easier testing.
    #
    # @example Basic usage
    #   class ProductRepository < BetterService::Repository::BaseRepository
    #     def initialize(model_class = Product)
    #       super
    #     end
    #   end
    #
    #   repo = ProductRepository.new
    #   products = repo.search({ status_eq: 'active' }, includes: [:category])
    #
    # @example With predicates
    #   repo.search({
    #     user_id_eq: user.id,
    #     status_in: ['pending', 'confirmed'],
    #     created_at_gteq: 1.week.ago
    #   }, order: 'created_at DESC', per_page: 20)
    #
    class BaseRepository
      attr_reader :model

      # Initialize repository with a model class
      #
      # @param model_class [Class, nil] ActiveRecord model class
      #   If nil, derives class name from repository name
      def initialize(model_class = nil)
        @model = model_class || derive_model_class
      end

      # Search records using predicates
      #
      # Supports flexible querying through predicates hash that gets
      # translated to ActiveRecord scopes via model's Searchable concern.
      #
      # @param predicates [Hash] Search predicates (e.g., { status_eq: 'active' })
      # @param page [Integer] Page number for pagination (default: 1)
      # @param per_page [Integer] Records per page (default: 20)
      # @param includes [Array] Associations to eager load
      # @param joins [Array] Associations to join
      # @param order [String, Hash, nil] Order clause
      # @param order_scope [Hash, nil] Named scope for ordering { field:, direction: }
      # @param limit [Integer, Symbol, nil] Limit results
      #   - 1: returns single record (first)
      #   - Integer > 1: limit to N records
      #   - nil: no limit (returns all)
      #   - :default: apply pagination
      # @return [ActiveRecord::Relation, Object, nil] Query result
      #
      # @example Basic search
      #   search({ status_eq: 'active' })
      #
      # @example With pagination
      #   search({ user_id_eq: 1 }, page: 2, per_page: 25)
      #
      # @example Single record
      #   search({ id_eq: 123 }, limit: 1)
      #
      # @example With eager loading
      #   search({}, includes: [:user, :comments], order: 'created_at DESC')
      def search(predicates = {}, page: 1, per_page: 20, includes: [],
                 joins: [], order: nil, order_scope: nil, limit: :default)
        cleaned_predicates = (predicates || {}).compact

        scope = build_base_scope(cleaned_predicates)
        scope = apply_joins(scope, joins)
        scope = apply_includes(scope, includes)
        scope = apply_ordering(scope, order, order_scope)
        apply_limit_or_pagination(scope, limit, page, per_page)
      end

      # Delegate basic ActiveRecord methods to model
      delegate :find, :find_by, :where, :all, :count, :exists?, to: :model

      # Build a new unsaved record
      #
      # @param attributes [Hash] Attributes for the new record
      # @return [ActiveRecord::Base] Unsaved model instance
      def build(attributes = {})
        model.new(attributes)
      end
      alias new build

      # Create a new record (may return invalid record)
      #
      # @param attributes [Hash] Attributes for the new record
      # @return [ActiveRecord::Base] Created model instance
      def create(attributes = {})
        model.create(attributes)
      end

      # Create a new record (raises on validation failure)
      #
      # @param attributes [Hash] Attributes for the new record
      # @return [ActiveRecord::Base] Created model instance
      # @raise [ActiveRecord::RecordInvalid] if validation fails
      def create!(attributes = {})
        model.create!(attributes)
      end

      # Update an existing record
      #
      # @param record_or_id [ActiveRecord::Base, Integer, String] Record or ID
      # @param attributes [Hash] Attributes to update
      # @return [ActiveRecord::Base] Updated model instance
      # @raise [ActiveRecord::RecordInvalid] if validation fails
      def update(record_or_id, attributes)
        record = resolve_record(record_or_id)
        record.update!(attributes)
        record
      end
      alias update! update

      # Destroy a record
      #
      # @param record_or_id [ActiveRecord::Base, Integer, String] Record or ID
      # @return [ActiveRecord::Base] Destroyed model instance
      def destroy(record_or_id)
        record = resolve_record(record_or_id)
        record.destroy!
        record
      end
      alias destroy! destroy

      # Delete a record without callbacks
      #
      # @param record_or_id [ActiveRecord::Base, Integer, String] Record or ID
      # @return [Integer] Number of deleted records
      def delete(record_or_id)
        id = record_or_id.respond_to?(:id) ? record_or_id.id : record_or_id
        model.where(id: id).delete_all
      end

      private

      # Resolve a record from ID or return the record itself
      #
      # @param record_or_id [ActiveRecord::Base, Integer, String] Record or ID
      # @return [ActiveRecord::Base] The resolved record
      def resolve_record(record_or_id)
        if record_or_id.is_a?(model)
          record_or_id
        else
          find(record_or_id)
        end
      end

      # Derive model class from repository name
      #
      # ProductRepository -> Product
      # Bookings::BookingRepository -> Bookings::Booking
      #
      # @return [Class] The derived model class
      # @raise [BetterService::Errors::Configuration::ConfigurationError]
      def derive_model_class
        class_name = self.class.name.gsub(/Repository$/, "")
        class_name.constantize
      rescue NameError
        raise Errors::Configuration::ConfigurationError,
              "Could not derive model class from #{self.class.name}. " \
              "Pass model_class explicitly to initialize."
      end

      # Build base scope from predicates
      #
      # @param predicates [Hash] Search predicates
      # @return [ActiveRecord::Relation] Base query scope
      def build_base_scope(predicates)
        if model.respond_to?(:search) && predicates.present?
          model.search(predicates)
        else
          model.all
        end
      end

      # Apply joins to scope
      #
      # @param scope [ActiveRecord::Relation] Current scope
      # @param joins [Array] Associations to join
      # @return [ActiveRecord::Relation] Scope with joins
      def apply_joins(scope, joins)
        return scope if joins.blank?

        scope.joins(*joins)
      end

      # Apply includes to scope
      #
      # @param scope [ActiveRecord::Relation] Current scope
      # @param includes [Array] Associations to eager load
      # @return [ActiveRecord::Relation] Scope with includes
      def apply_includes(scope, includes)
        return scope if includes.blank?

        scope.includes(*includes)
      end

      # Apply ordering to scope
      #
      # @param scope [ActiveRecord::Relation] Current scope
      # @param order [String, Hash, nil] Order clause
      # @param order_scope [Hash, nil] Named scope for ordering
      # @return [ActiveRecord::Relation] Ordered scope
      def apply_ordering(scope, order, order_scope)
        if order_scope.present?
          scope_name = "#{order_scope[:field]}_#{order_scope[:direction]}"
          scope.respond_to?(scope_name) ? scope.send(scope_name) : scope
        elsif order.present?
          scope.order(order)
        else
          scope
        end
      end

      # Apply limit or pagination to scope
      #
      # @param scope [ActiveRecord::Relation] Current scope
      # @param limit [Integer, Symbol, nil] Limit specification
      # @param page [Integer] Page number
      # @param per_page [Integer] Records per page
      # @return [ActiveRecord::Relation, Object, nil] Limited scope or record
      def apply_limit_or_pagination(scope, limit, page, per_page)
        case limit
        when 1
          scope.first
        when Integer
          scope.limit(limit)
        when nil
          scope
        when :default
          paginate(scope, page: page, per_page: per_page)
        else
          paginate(scope, page: page, per_page: per_page)
        end
      end

      # Apply pagination to scope
      #
      # @param scope [ActiveRecord::Relation] Current scope
      # @param page [Integer] Page number
      # @param per_page [Integer] Records per page
      # @return [ActiveRecord::Relation] Paginated scope
      def paginate(scope, page:, per_page:)
        offset_value = ([ page.to_i, 1 ].max - 1) * per_page.to_i
        scope.offset(offset_value).limit(per_page)
      end
    end
  end
end
