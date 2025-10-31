# frozen_string_literal: true

module BetterService
  # Base error class for BetterService
  class Error < StandardError; end

  # Raised when a service is missing a required schema definition
  class SchemaRequiredError < Error; end
end
