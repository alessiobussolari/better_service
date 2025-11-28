# frozen_string_literal: true

require "dry-schema"
require_relative "../concerns/serviceable/messageable"
require_relative "../concerns/serviceable/validatable"
require_relative "../concerns/serviceable/authorizable"
require_relative "../concerns/serviceable/presentable"
require_relative "../concerns/serviceable/cacheable"
require_relative "../concerns/serviceable/viewable"
require_relative "../concerns/serviceable/transactional"
require_relative "../concerns/instrumentation"

module BetterService
  module Services
  class Base
    class_attribute :_allow_nil_user, default: false
    class_attribute :_action_name, default: nil
    class_attribute :_search_block, default: nil
    class_attribute :_process_block, default: nil
    class_attribute :_transform_block, default: nil
    class_attribute :_respond_block, default: nil
    class_attribute :_auto_invalidate_cache, default: false

    include Concerns::Serviceable::Messageable
    include Concerns::Serviceable::Validatable
    include Concerns::Serviceable::Authorizable
    include Concerns::Serviceable::Presentable
    include Concerns::Serviceable::Viewable

    # Prepend Transactional so it can wrap the process method
    prepend Concerns::Serviceable::Transactional

    # Default empty schema - subclasses should override
    schema do
      # Override in subclass with specific validations
    end

    attr_reader :user, :params

    def initialize(user, params: {})
      validate_user_presence!(user) unless self.class._allow_nil_user
      validate_schema_presence!
      @user = user
      @params = safe_params_to_hash(params)
      validate_params!
    end

    # DSL methods to define phase blocks

    # Configure whether this service allows nil user
    #
    # @param value [Boolean] Whether to allow nil user (default: true)
    # @return [void]
    #
    # @example Allow nil user
    #   class PublicService < BetterService::Services::Base
    #     allow_nil_user true
    #   end
    #
    # @example Require user (default)
    #   class PrivateService < BetterService::Services::Base
    #     allow_nil_user false
    #   end
    def self.allow_nil_user(value = true)
      self._allow_nil_user = value
    end

    # Configure the action name for metadata tracking
    #
    # @param name [Symbol, String] The action name (e.g., :publish, :approve)
    # @return [void]
    #
    # @example Custom action service
    #   class Order::ApproveService < Order::BaseService
    #     performed_action :approve
    #   end
    #
    # @example CRUD service with standard action
    #   class Product::CreateService < Product::BaseService
    #     performed_action :created
    #   end
    def self.performed_action(name)
      self._action_name = name.to_sym
    end

    def self.search_with(&block)
      self._search_block = block
    end

    def self.process_with(&block)
      self._process_block = block
    end

    def self.transform_with(&block)
      self._transform_block = block
    end

    def self.respond_with(&block)
      self._respond_block = block
    end

    # Configure automatic cache invalidation after write operations
    #
    # @param enabled [Boolean] Whether to automatically invalidate cache (default: true)
    # @return [void]
    #
    # @example Enable automatic cache invalidation (default for Create/Update/Destroy)
    #   class Products::CreateService < CreateService
    #     cache_contexts :products, :category_products
    #     # Cache is automatically invalidated after successful create
    #   end
    #
    # @example Disable automatic cache invalidation
    #   class Products::CreateService < CreateService
    #     auto_invalidate_cache false
    #
    #     process_with do |data|
    #       product = Product.create!(params)
    #       invalidate_cache_for(user) if should_invalidate?  # Manual control
    #       { resource: product }
    #     end
    #   end
    def self.auto_invalidate_cache(enabled = true)
      self._auto_invalidate_cache = enabled
    end

    # Main entry point - executes the 5-phase flow
    def call
      # Validation already raises ValidationError in initialize
      # Authorization already raises AuthorizationError
      authorize!

      data = search
      processed = process(data)

      # Auto-invalidate cache after write operations if configured
      if should_auto_invalidate_cache?
        invalidate_cache_for(user)
      end

      transformed = transform(processed)
      result = respond(transformed)

      # Phase 5: Viewer (if enabled)
      if respond_to?(:viewer_enabled?, true) && viewer_enabled?
        view_config = execute_viewer(processed, transformed, result)
        result = result.merge(view: view_config)
      end

      result
    rescue Errors::Runtime::ValidationError, Errors::Runtime::AuthorizationError
      # Let validation and authorization errors propagate without wrapping
      raise
    rescue ActiveRecord::RecordNotFound => e
      handle_not_found_error(e)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      handle_database_error(e)
    rescue StandardError => e
      handle_unexpected_error(e)
    end

    # Include Cacheable AFTER call method is defined so it can wrap it
    # This must be before Instrumentation prepend so cache works correctly
    include Concerns::Serviceable::Cacheable

    private

    # Phase 1: Search - Load raw data (override in subclass)
    def search
      if self.class._search_block
        instance_exec(&self.class._search_block)
      else
        {}
      end
    end

    # Phase 2: Process - Transform and aggregate data (override in subclass)
    def process(data)
      if self.class._process_block
        instance_exec(data, &self.class._process_block)
      else
        data
      end
    end

    # Phase 3: Transform - Handled by Presentable concern

    # Phase 4: Respond - Format response (override in service types or with respond_with block)
    def respond(data)
      if self.class._respond_block
        instance_exec(data, &self.class._respond_block)
      else
        success_result("Operation completed successfully", data)
      end
    end

    # Check if cache should be automatically invalidated
    #
    # Auto-invalidation happens when:
    # 1. auto_invalidate_cache is enabled (true)
    # 2. cache_contexts are defined (something to invalidate)
    # 3. Service is a write operation (Create/Update/Destroy)
    #
    # @return [Boolean] Whether cache should be invalidated
    def should_auto_invalidate_cache?
      return false unless self.class._auto_invalidate_cache
      return false unless self.class.respond_to?(:_cache_contexts)
      return false unless self.class._cache_contexts.present?

      # Only auto-invalidate for write operations
      is_a?(Services::CreateService) ||
        is_a?(Services::UpdateService) ||
        is_a?(Services::DestroyService)
    end

    # Error handlers for runtime errors
    #
    # These methods handle unexpected errors during service execution by raising
    # appropriate runtime exceptions. They log the error and wrap it with service context.

    # Handle resource not found errors (ActiveRecord::RecordNotFound)
    #
    # @param error [ActiveRecord::RecordNotFound] The original not found error
    # @raise [Errors::Runtime::ResourceNotFoundError] Wrapped error with context
    def handle_not_found_error(error)
      Rails.logger.error "Resource not found in #{self.class.name}: #{error.message}" if defined?(Rails)

      raise Errors::Runtime::ResourceNotFoundError.new(
        "Resource not found: #{error.message}",
        code: BetterService::ErrorCodes::RESOURCE_NOT_FOUND,
        original_error: error,
        context: { service: self.class.name, params: @params }
      )
    end

    # Handle database errors (ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved)
    #
    # @param error [ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved] The original database error
    # @raise [Errors::Runtime::DatabaseError] Wrapped error with context
    def handle_database_error(error)
      Rails.logger.error "Database error in #{self.class.name}: #{error.message}" if defined?(Rails)
      Rails.logger.error error.backtrace.join("\n") if defined?(Rails)

      raise Errors::Runtime::DatabaseError.new(
        "Database error: #{error.message}",
        code: BetterService::ErrorCodes::DATABASE_ERROR,
        original_error: error,
        context: { service: self.class.name, params: @params }
      )
    end

    # Handle unexpected errors (all other StandardError)
    #
    # @param error [StandardError] The original unexpected error
    # @raise [Errors::Runtime::ExecutionError] Wrapped error with context
    def handle_unexpected_error(error)
      Rails.logger.error "Unexpected error in #{self.class.name}: #{error.message}" if defined?(Rails)
      Rails.logger.error error.backtrace.join("\n") if defined?(Rails)

      raise Errors::Runtime::ExecutionError.new(
        "Service execution failed: #{error.message}",
        code: BetterService::ErrorCodes::EXECUTION_ERROR,
        original_error: error,
        context: { service: self.class.name, params: @params }
      )
    end

    def validate_user_presence!(user)
      return if user.present?

      raise Errors::Configuration::NilUserError,
            "User cannot be nil for #{self.class.name}. " \
            "Add 'allow_nil_user true' in config block if this is intentional."
    end

    def validate_schema_presence!
      return if self.class.schema_defined?

      raise Errors::Configuration::SchemaRequiredError,
            "#{self.class.name} must define a schema block. " \
            "Add 'schema do ... end' to validate params."
    end

    def safe_params_to_hash(params)
      return {} if params.nil?

      # Handle ActionController::Parameters by converting to unsafe hash first
      if params.respond_to?(:to_unsafe_h)
        params.to_unsafe_h.deep_symbolize_keys
      elsif params.respond_to?(:to_h)
        params.to_h.deep_symbolize_keys
      elsif params.is_a?(Hash)
        params.deep_symbolize_keys
      else
        {}
      end
    rescue StandardError => e
      Rails.logger.warn "Failed to convert params to hash: #{e.message}" if defined?(Rails)
      {}
    end

    def success_result(message, data = {})
      # Extract metadata if provided in data, or initialize empty
      provided_metadata = data.delete(:metadata) || {}

      # Build metadata with action if action_name is set
      metadata = {}
      metadata[:action] = self.class._action_name if self.class._action_name.present?
      metadata.merge!(provided_metadata)

      {
        success: true,
        message: message,
        metadata: metadata,
        **data
      }
    end

    # Build a failure response hash
    #
    # @param error_message [String] Human-readable error message
    # @param errors [Hash, Array] Validation errors in various formats
    # @return [Hash] Standardized failure response
    #
    # @example Simple error
    #   failure_result("Record not found")
    #
    # @example With validation errors
    #   failure_result("Validation failed", { email: ["is invalid"] })
    def failure_result(error_message, errors = {})
      {
        success: false,
        error: error_message,
        errors: format_errors_for_response(errors)
      }
    end

    # Build a validation failure response with the failed resource
    #
    # Used when ActiveRecord validation fails and the form
    # needs to be re-rendered with the invalid model.
    #
    # @param failed_resource [ActiveRecord::Base] Model with validation errors
    # @return [Hash] Failure response with errors and failed_resource
    #
    # @example
    #   user = User.new(invalid_params)
    #   user.valid? # => false
    #   validation_failure_result(user)
    def validation_failure_result(failed_resource)
      {
        success: false,
        errors: format_model_validation_errors(failed_resource.errors),
        failed_resource: failed_resource
      }
    end

    # Check if data contains an error (for phase flow control)
    #
    # @param data [Hash] Data from previous phase
    # @return [Boolean] true if data contains error
    #
    # @example
    #   def process(data)
    #     return data if error?(data)  # Pass through errors
    #     # ... processing logic
    #   end
    def error?(data)
      data.is_a?(Hash) && (data[:error] || data[:success] == false)
    end

    # Format errors into standard array format
    #
    # @param errors [Hash, Array] Errors in various formats
    # @return [Array<Hash>] Standardized error array
    def format_errors_for_response(errors)
      case errors
      when Hash
        errors.flat_map do |key, messages|
          Array(messages).map { |msg| { key: key.to_s, message: msg } }
        end
      when Array
        errors.map do |err|
          if err.is_a?(Hash) && err[:key] && err[:message]
            err
          elsif err.is_a?(String)
            { key: "base", message: err }
          else
            { key: "base", message: err.to_s }
          end
        end
      else
        []
      end
    end

    # Format ActiveRecord/ActiveModel errors into standard format
    #
    # Used specifically for ActiveModel::Errors objects (from Rails models).
    # For Dry::Schema validation errors, the Validatable concern has its own
    # format_validation_errors method.
    #
    # @param errors [ActiveModel::Errors] ActiveRecord errors object
    # @return [Array<Hash>] Standardized error array
    def format_model_validation_errors(errors)
      return [] if errors.blank?

      errors.map do |error|
        {
          key: error.attribute.to_s,
          message: error.message
        }
      end
    end

    # Prepend Instrumentation at the end, after call method is defined
    # This wraps the entire call method (including cache logic from Cacheable)
    prepend Concerns::Instrumentation
  end
  end
end
