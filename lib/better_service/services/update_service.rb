# frozen_string_literal: true

require_relative "base"

module BetterService
  module Services
  # UpdateService - Specialized service for updating existing resources
  #
  # Returns: { resource: {}, metadata: { action: :updated } }
  #
  # Example:
  #   class Bookings::UpdateService < BetterService::Services::UpdateService
  #     schema do
  #       required(:id).filled(:integer)
  #       optional(:title).filled(:string)
  #     end
  #
  #     search_with do
  #       { resource: user.bookings.find(params[:id]) }
  #     end
  #
  #     process_with do |data|
  #       booking = data[:resource]
  #       booking.update!(params.except(:id))
  #       { resource: booking }
  #     end
  #   end
  class UpdateService < Services::Base
    # Set action_name for metadata
    self._action_name = :updated

    # Enable database transactions by default for update operations
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
        result = success_result("Resource updated successfully", data)
      end

      # Ensure resource key exists (default to nil if not provided)
      result[:resource] ||= nil

      result
    end
  end
  end
end
