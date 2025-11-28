# frozen_string_literal: true

require_relative "base"

module BetterService
  module Services
  # DestroyService - Specialized service for deleting resources
  #
  # Returns: { resource: {}, metadata: { action: :deleted } }
  #
  # Example:
  #   class Orders::DestroyService < BetterService::Services::DestroyService
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
  #       order.destroy!
  #       { resource: order }
  #     end
  #   end
  class DestroyService < Services::Base
    # Set action_name for metadata
    self._action_name = :deleted

    # Enable database transactions by default for destroy operations
    with_transaction true

    # Enable automatic cache invalidation for destroy operations
    self._auto_invalidate_cache = true

    # Default schema - requires id parameter
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
        result = success_result("Resource deleted successfully", data)
      end

      # Ensure resource key exists (default to nil if not provided)
      result[:resource] ||= nil

      result
    end
  end
  end
end
