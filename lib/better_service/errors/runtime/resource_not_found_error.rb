# frozen_string_literal: true

module BetterService
  module Errors
    module Runtime
      # Raised when a required resource is not found
      #
      # This error wraps ActiveRecord::RecordNotFound exceptions raised during
      # service execution (usually in the search phase).
      #
      # @example Resource not found
      #   class UserShowService < BetterService::Services::ShowService
      #     model_class User
      #
      #     schema do
      #       required(:id).filled(:integer)
      #     end
      #   end
      #
      #   UserShowService.new(user, params: { id: 99999 }).call
      #   # => raises ResourceNotFoundError wrapping ActiveRecord::RecordNotFound
      #
      # @example In custom service
      #   class MyService < BetterService::Services::Base
      #     schema { required(:user_id).filled(:integer) }
      #
      #     search_with do
      #       User.find(params[:user_id])  # Raises RecordNotFound if not exists
      #     end
      #   end
      #
      #   MyService.new(user, params: { user_id: 99999 }).call
      #   # => raises ResourceNotFoundError
      class ResourceNotFoundError < BetterService::Errors::Runtime::RuntimeError
        def initialize(message = "Resource not found", code: :resource_not_found, context: {}, original_error: nil)
          super(message, code: code, context: context, original_error: original_error)
        end
      end
    end
  end
end
