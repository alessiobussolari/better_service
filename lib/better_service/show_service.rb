# frozen_string_literal: true

require_relative "base"

module BetterService
  # ShowService - Specialized service for single resource detail endpoints
  #
  # Returns: { resource: {}, metadata: { action: :show } }
  #
  # Example:
  #   class Bookings::ShowService < BetterService::ShowService
  #     search_with do
  #       { resource: user.bookings.find(params[:id]) }
  #     end
  #   end
  class ShowService < Base
    # Set action_name for metadata
    self._action_name = :show

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
        result = success_result("Operation completed successfully", data)
      end

      # Ensure resource key exists (default to nil if not provided)
      result[:resource] ||= nil

      result
    end
  end
end
