# frozen_string_literal: true

module BetterService
  module Concerns
    module Serviceable
    module Messageable
      extend ActiveSupport::Concern

      included do
        class_attribute :_messages_namespace, default: nil
      end

      class_methods do
        def messages_namespace(namespace)
          self._messages_namespace = namespace
        end
      end

      private

      # Get translated message with fallback support
      #
      # Lookup order:
      # 1. Custom namespace: "#{namespace}.services.#{key_path}"
      # 2. Default namespace: "better_service.services.default.#{action}"
      # 3. Key itself as final fallback
      #
      # @param key_path [String] Message key path (e.g., "create.success")
      # @param interpolations [Hash] Variables to interpolate
      # @return [String] Translated message
      def message(key_path, interpolations = {})
        # If no namespace defined, use default BetterService messages
        if self.class._messages_namespace.nil?
          # Extract action from key_path (e.g., "create.success" -> "created")
          action = extract_action_from_key(key_path)
          default_key = "better_service.services.default.#{action}"
          return I18n.t(default_key, default: key_path, **interpolations)
        end

        # Try custom namespace first, fallback to default, then to key itself
        full_key = "#{self.class._messages_namespace}.services.#{key_path}"
        action = extract_action_from_key(key_path)
        fallback_key = "better_service.services.default.#{action}"

        # I18n supports array of fallback keys: try each in order
        I18n.t(full_key, default: [fallback_key.to_sym, key_path], **interpolations)
      end

      # Extract action name from key path for fallback lookup
      #
      # Examples:
      #   "create.success" -> "created"
      #   "update.success" -> "updated"
      #   "destroy.success" -> "deleted"
      #   "custom_action" -> "action_completed"
      #
      # @param key_path [String] Full key path
      # @return [String] Action name for default messages
      def extract_action_from_key(key_path)
        # Handle common patterns
        case key_path
        when /create/i then "created"
        when /update/i then "updated"
        when /destroy|delete/i then "deleted"
        when /index|list/i then "listed"
        when /show/i then "shown"
        else "action_completed"
        end
      end

      # ============================================
      # RESPONSE HELPERS FOR TUPLE FORMAT
      # ============================================

      # Build a failure response hash for validation failures
      # Use this when using save (not save!) to handle AR validation gracefully
      #
      # @param record [ActiveRecord::Base] The record with validation errors
      # @param custom_message [String, nil] Optional custom message
      # @return [Hash] Failure response hash (for use in process_with/respond_with)
      #
      # @example In process_with block
      #   process_with do |data|
      #     product = user.products.build(params)
      #
      #     if product.save
      #       { object: product }
      #     else
      #       failure_for(product)
      #     end
      #   end
      def failure_for(record, custom_message = nil)
        {
          object: record,
          success: false,
          message: custom_message || default_failure_message(record)
        }
      end

      # Build a success response hash
      #
      # @param object [Object] The object to return (AR model, array, etc.)
      # @param custom_message [String, nil] Optional custom message
      # @return [Hash] Success response hash (for use in respond_with)
      #
      # @example In respond_with block
      #   respond_with do |data|
      #     return data if data[:success] == false
      #     success_for(data[:object], "Product created!")
      #   end
      def success_for(object, custom_message = nil)
        {
          object: object,
          success: true,
          message: custom_message || default_success_message
        }
      end

      # Generate default failure message based on record state
      #
      # @param record [ActiveRecord::Base] The failed record
      # @return [String] Failure message
      def default_failure_message(record)
        model_name = record.class.name.underscore.humanize.downcase
        if record.new_record?
          message("create.failure", default: "Failed to create #{model_name}")
        else
          message("update.failure", default: "Failed to update #{model_name}")
        end
      end

      # Generate default success message based on action
      #
      # @return [String] Success message
      def default_success_message
        action = self.class._action_name || :action
        message("#{action}.success", default: "Operation completed successfully")
      end
    end
    end
  end
end
