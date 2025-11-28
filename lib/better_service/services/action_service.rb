# frozen_string_literal: true

require_relative "base"

module BetterService
  module Services
  # ActionService - Specialized service for custom actions/transitions
  #
  # Returns: { resource: {}, metadata: { action: :custom_action_name } }
  #
  # Example:
  #   class Orders::ConfirmService < BetterService::Services::ActionService
  #     action_name :confirmed  # Sets metadata action
  #
  #     schema do
  #       required(:id).filled(:integer)
  #     end
  #
  #     search_with do
  #       { resource: user.orders.find(params[:id]) }
  #     end
  #
  #     process_with do |data|
  #       order = data[:resource]
  #       order.update!(status: 'confirmed', confirmed_at: Time.current)
  #       { resource: order }
  #     end
  #   end
  class ActionService < Services::Base
    # Default action_name to nil - subclasses MUST set it
    self._action_name = nil

    def self.action_name(name)
      self._action_name = name.to_sym
    end

    # Default schema - requires id parameter for actions
    schema do
      required(:id).filled
    end

    private

    # Override respond to ensure resource key is present
    def respond(data)
      # Get base result (from custom respond_with block or default)
      if self.class._respond_block
        result = instance_exec(data, &self.class._respond_block)
      else
        result = success_result("Action completed successfully", data)
      end

      # Ensure resource key exists (default to nil if not provided)
      result[:resource] ||= nil

      result
    end
  end
  end
end
