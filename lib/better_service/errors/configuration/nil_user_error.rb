# frozen_string_literal: true

module BetterService
  module Errors
    module Configuration
      # Raised when a service is initialized with nil user when user is required
      #
      # By default, all BetterService services require a user object. This error is raised
      # during initialization if user is nil and `allow_nil_user` is not configured.
      #
      # @example Service called with nil user (will raise error)
      #   class MyService < BetterService::Services::Base
      #     schema do
      #       required(:name).filled(:string)
      #     end
      #   end
      #
      #   MyService.new(nil, params: { name: "test" })
      #   # => raises NilUserError
      #
      # @example Allowing nil user
      #   class MyService < BetterService::Services::Base
      #     config do
      #       allow_nil_user true
      #     end
      #
      #     schema do
      #       required(:name).filled(:string)
      #     end
      #   end
      #
      #   MyService.new(nil, params: { name: "test" })  # OK
      class NilUserError < ConfigurationError
      end
    end
  end
end
