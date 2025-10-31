# frozen_string_literal: true

require_relative "base"

module BetterService
  # IndexService - Specialized service for list/collection endpoints
  #
  # Returns: { items: [], metadata: { action: :index, stats: {}, pagination: {} } }
  #
  # Example:
  #   class Bookings::IndexService < BetterService::IndexService
  #     search_with do
  #       { items: user.bookings.to_a }
  #     end
  #
  #     process_with do |data|
  #       {
  #         items: data[:items],
  #         metadata: {
  #           stats: { total: data[:items].count },
  #           pagination: { page: params[:page] || 1 }
  #         }
  #       }
  #     end
  #   end
  class IndexService < Base
    # Set action_name for metadata
    self._action_name = :index

    # Default schema - can be overridden in subclasses
    schema do
      optional(:page).filled(:integer, gteq?: 1)
      optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
      optional(:search).maybe(:string)
    end

    private

    # Override respond to ensure items key is present
    def respond(data)
      # Get base result (from custom respond_with block or default)
      if self.class._respond_block
        result = instance_exec(data, &self.class._respond_block)
      else
        result = success_result("Operation completed successfully", data)
      end

      # Ensure items key exists (default to empty array if not provided)
      result[:items] ||= []

      result
    end
  end
end
