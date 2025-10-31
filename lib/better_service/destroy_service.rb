# frozen_string_literal: true

require_relative "base"

module BetterService
  # DestroyService - Specialized service for deleting resources
  #
  # Returns: { resource: {}, metadata: { action: :deleted } }
  #
  # Example:
  #   class Bookings::DestroyService < BetterService::DestroyService
  #     schema do
  #       required(:id).filled(:integer)
  #     end
  #
  #     search_with do
  #       { resource: user.bookings.find(params[:id]) }
  #     end
  #
  #     process_with do |data|
  #       booking = data[:resource]
  #       booking.destroy!
  #       { resource: booking }
  #     end
  #   end
  class DestroyService < Base
    # Set action_name for metadata
    self._action_name = :deleted

    # Enable database transactions by default for destroy operations
    with_transaction true

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
