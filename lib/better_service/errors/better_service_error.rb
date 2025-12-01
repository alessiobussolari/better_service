# frozen_string_literal: true

module BetterService
  # Base exception class for all BetterService errors
  #
  # This class provides rich error information including error codes, context,
  # original errors, and structured metadata for debugging and logging.
  #
  # @example Basic usage
  #   raise BetterServiceError.new(
  #     "Something went wrong",
  #     code: :custom_error,
  #     context: { user_id: 123, action: "create" }
  #   )
  #
  # @example With original error
  #   begin
  #     dangerous_operation
  #   rescue StandardError => e
  #     raise BetterServiceError.new(
  #       "Operation failed",
  #       code: :operation_failed,
  #       original_error: e,
  #       context: { operation: "dangerous_operation" }
  #     )
  #   end
  #
  # @example Accessing error information
  #   begin
  #     service.call
  #   rescue BetterServiceError => e
  #     logger.error e.to_h
  #     # => {
  #     #   error_class: "BetterService::Errors::Runtime::ValidationError",
  #     #   message: "Validation failed",
  #     #   code: :validation_failed,
  #     #   timestamp: "2025-11-09T10:30:00Z",
  #     #   context: { service: "UserService", validation_errors: {...} },
  #     #   original_error: nil,
  #     #   backtrace: [...]
  #     # }
  #   end
  class BetterServiceError < StandardError
    # @return [Symbol, nil] Error code for programmatic handling
    attr_reader :code

    # @return [Exception, nil] Original exception that caused this error
    attr_reader :original_error

    # @return [Hash] Additional context about the error
    attr_reader :context

    # @return [Time] When the error was raised
    attr_reader :timestamp

    # Initialize a new BetterService error
    #
    # @param message [String, nil] Human-readable error message
    # @param code [Symbol, nil] Error code for programmatic handling
    # @param original_error [Exception, nil] Original exception that caused this error
    # @param context [Hash] Additional context about the error (service name, params, etc.)
    def initialize(message = nil, code: nil, original_error: nil, context: {})
      super(message)
      @code = code
      @original_error = original_error
      @context = context || {}
      @timestamp = Time.current
    end

    # Convert error to a structured hash
    #
    # @return [Hash] Hash representation with all error information
    def to_h
      {
        error_class: self.class.name,
        message: message,
        code: code,
        timestamp: timestamp.iso8601,
        context: context,
        original_error: original_error_info,
        backtrace: backtrace&.first(10) || []
      }
    end

    # Get detailed error message with context
    #
    # @return [String] Detailed message including context
    def detailed_message
      parts = [ message ]
      parts << "Code: #{code}" if code
      parts << "Context: #{context.inspect}" if context.any?
      parts << "Original: #{original_error.class.name}: #{original_error.message}" if original_error
      parts.join(" | ")
    end

    # Enhanced inspect for debugging
    #
    # @return [String] Detailed string representation
    def inspect
      "#<#{self.class.name}: #{detailed_message}>"
    end

    # Override backtrace to include original error's backtrace
    #
    # @return [Array<String>] Combined backtrace
    def backtrace
      trace = super || []

      if original_error && original_error.backtrace
        trace + [ "--- Original Error Backtrace ---" ] + original_error.backtrace
      else
        trace
      end
    end

    private

    # Get original error information as hash
    #
    # @return [Hash, nil] Original error details or nil
    def original_error_info
      return nil unless original_error

      {
        class: original_error.class.name,
        message: original_error.message,
        backtrace: original_error.backtrace&.first(5) || []
      }
    end
  end

  # Standard error codes used in BetterService responses
  #
  # These codes are used for both hash responses and exception codes,
  # providing consistent error identification across the system.
  #
  # @example Using error codes in exceptions
  #   raise Errors::Runtime::ValidationError.new(
  #     "Validation failed",
  #     code: ErrorCodes::VALIDATION_FAILED,
  #     context: { validation_errors: {...} }
  #   )
  #
  # @example Handling errors by code
  #   begin
  #     service.call
  #   rescue BetterServiceError => e
  #     case e.code
  #     when ErrorCodes::VALIDATION_FAILED
  #       render json: { errors: e.context[:validation_errors] }, status: :unprocessable_entity
  #     when ErrorCodes::UNAUTHORIZED
  #       render json: { error: e.message }, status: :forbidden
  #     end
  #   end
  module ErrorCodes
    # ============================================
    # BUSINESS LOGIC ERROR CODES
    # ============================================

    # Validation failed - input parameters are invalid
    #
    # Used when Dry::Schema validation fails.
    # The error will include validation details in context.
    #
    # @example
    #   raise Errors::Runtime::ValidationError.new(
    #     "Validation failed",
    #     code: :validation_failed,
    #     context: {
    #       validation_errors: { email: ["is invalid"], age: ["must be greater than 18"] }
    #     }
    #   )
    VALIDATION_FAILED = :validation_failed

    # Authorization failed - user doesn't have permission
    #
    # Used when the authorize_with block returns false.
    #
    # @example
    #   raise Errors::Runtime::AuthorizationError.new(
    #     "Not authorized to perform this action",
    #     code: :unauthorized,
    #     context: { user_id: 123, action: "destroy" }
    #   )
    UNAUTHORIZED = :unauthorized

    # ============================================
    # PROGRAMMING ERROR CODES
    # ============================================

    # Schema is missing or invalid
    SCHEMA_REQUIRED = :schema_required

    # Service configuration is invalid
    CONFIGURATION_ERROR = :configuration_error

    # ============================================
    # RUNTIME ERROR CODES
    # ============================================

    # Unexpected error during service execution
    EXECUTION_ERROR = :execution_error

    # Required resource was not found
    RESOURCE_NOT_FOUND = :resource_not_found

    # Database transaction failed
    TRANSACTION_ERROR = :transaction_error

    # Database operation failed (validation errors, save failures)
    DATABASE_ERROR = :database_error

    # Workflow execution failed
    WORKFLOW_FAILED = :workflow_failed

    # Workflow step failed
    STEP_FAILED = :step_failed

    # Workflow rollback failed
    ROLLBACK_FAILED = :rollback_failed

    # Service returned invalid result type (not BetterService::Result)
    INVALID_RESULT = :invalid_result
  end
end

# Require all error classes
require_relative "configuration/configuration_error"
require_relative "configuration/schema_required_error"
require_relative "configuration/invalid_schema_error"
require_relative "configuration/invalid_configuration_error"
require_relative "configuration/nil_user_error"

require_relative "runtime/runtime_error"
require_relative "runtime/execution_error"
require_relative "runtime/transaction_error"
require_relative "runtime/resource_not_found_error"
require_relative "runtime/database_error"
require_relative "runtime/validation_error"
require_relative "runtime/authorization_error"
require_relative "runtime/invalid_result_error"

require_relative "workflowable/configuration/workflow_configuration_error"
require_relative "workflowable/configuration/step_not_found_error"
require_relative "workflowable/configuration/invalid_step_error"
require_relative "workflowable/configuration/duplicate_step_error"

require_relative "workflowable/runtime/workflow_runtime_error"
require_relative "workflowable/runtime/workflow_execution_error"
require_relative "workflowable/runtime/step_execution_error"
require_relative "workflowable/runtime/rollback_error"

# Namespace for all BetterService errors
module BetterService
  module Errors
    # Namespace for configuration/programming errors
    module Configuration
    end

    # Namespace for runtime errors
    module Runtime
    end

    # Namespace for workflow-related errors
    module Workflowable
      # Namespace for workflow configuration errors
      module Configuration
      end

      # Namespace for workflow runtime errors
      module Runtime
      end
    end
  end
end
