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
      @validation_errors = {}
      validate_params!
    end

    # DSL methods to define phase blocks
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

    # Main entry point - executes the 5-phase flow
    def call
      # Validation already raises ValidationError in initialize
      # Authorization already raises AuthorizationError
      authorize!

      data = search
      processed = process(data)
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

    # Phase 4: Respond - Handled by Viewable concern

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

    def failure_result(message, errors = {}, code: nil)
      result = {
        success: false,
        error: message,
        errors: errors
      }
      result[:code] = code if code
      result
    end

    def error_result(message, code: nil)
      result = {
        success: false,
        errors: [message]
      }
      result[:code] = code if code
      result
    end

    # Prepend Instrumentation at the end, after call method is defined
    # This wraps the entire call method (including cache logic from Cacheable)
    prepend Concerns::Instrumentation
  end
  end
end
