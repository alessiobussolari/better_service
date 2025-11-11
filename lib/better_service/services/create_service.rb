# frozen_string_literal: true

require_relative "base"

module BetterService
  module Services
  # CreateService - Specialized service for creating new resources
  #
  # Returns: { resource: {}, metadata: { action: :created } }
  #
  # Example:
  #   class Bookings::CreateService < BetterService::Services::CreateService
  #     schema do
  #       required(:title).filled(:string)
  #       required(:date).filled(:date)
  #     end
  #
  #     search_with do
  #       {}
  #     end
  #
  #     process_with do |data|
  #       booking = user.bookings.create!(
  #         title: params[:title],
  #         date: params[:date]
  #       )
  #       { resource: booking }
  #     end
  #   end
  class CreateService < Services::Base
    # Set action_name for metadata
    self._action_name = :created

    # Enable database transactions by default for create operations
    with_transaction true

    # Default empty schema - subclasses MUST override with specific validations
    schema do
      # Override in subclass with required fields
    end

    private

    # Override respond to ensure resource key is present
    def respond(data)
      # Get base result (from custom respond_with block or default)
      if self.class._respond_block
        result = instance_exec(data, &self.class._respond_block)
      else
        result = success_result("Resource created successfully", data)
      end

      # Ensure resource key exists (default to nil if not provided)
      result[:resource] ||= nil

      result
    end
  end
  end
end
