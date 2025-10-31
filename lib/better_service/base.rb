# frozen_string_literal: true

require "dry-schema"
require_relative "concerns/messageable"
require_relative "concerns/validatable"
require_relative "concerns/authorizable"
require_relative "concerns/presentable"
require_relative "concerns/cacheable"
require_relative "concerns/viewable"
require_relative "concerns/transactional"

module BetterService
  class Base
    class_attribute :_allow_nil_user, default: false
    class_attribute :_action_name, default: nil
    class_attribute :_search_block, default: nil
    class_attribute :_process_block, default: nil
    class_attribute :_transform_block, default: nil
    class_attribute :_respond_block, default: nil

    include Concerns::Messageable
    include Concerns::Validatable
    include Concerns::Authorizable
    include Concerns::Presentable
    include Concerns::Viewable

    # Prepend Transactional last so it can wrap the process method
    prepend Concerns::Transactional

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
      return failure_result("Validation failed", @validation_errors) unless valid?

      # Authorization check (fail fast before search)
      auth_result = authorize!
      return auth_result if auth_result

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
    rescue StandardError => e
      handle_error(e)
    end

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

    # Error handler
    def handle_error(error)
      Rails.logger.error "Service error: #{error.message}" if defined?(Rails)
      Rails.logger.error error.backtrace.join("\n") if defined?(Rails)

      failure_result("An error occurred: #{error.message}")
    end

    def validate_user_presence!(user)
      return if user.present?

      raise ArgumentError,
            "User cannot be nil for #{self.class.name}. " \
            "Add 'allow_nil_user true' in config block if this is intentional."
    end

    def validate_schema_presence!
      return if self.class.schema_defined?

      raise SchemaRequiredError,
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

    # Include Cacheable (uses method wrapping via module trick)
    include Concerns::Cacheable
  end
end
