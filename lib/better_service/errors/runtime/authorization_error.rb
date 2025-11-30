# frozen_string_literal: true

module BetterService
  module Errors
    module Runtime
      # Raised when user is not authorized to perform the action
      #
      # This error is raised when the authorize_with block returns false.
      # Authorization checks happen before the service execution begins.
      #
      # @example Authorization failure
      #   class Post::DestroyService < BetterService::Services::DestroyService
      #     model_class Post
      #
      #     schema do
      #       required(:id).filled(:integer)
      #     end
      #
      #     authorize_with do
      #       resource.user_id == user.id  # Only owner can delete
      #     end
      #   end
      #
      #   # User tries to delete someone else's post
      #   Post::DestroyService.new(current_user, params: { id: other_users_post_id }).call
      #   # => raises AuthorizationError
      #
      # @example Handling authorization errors
      #   begin
      #     MyService.new(user, params: params).call
      #   rescue BetterService::Errors::Runtime::AuthorizationError => e
      #     render json: { error: e.message }, status: :forbidden
      #   end
      class AuthorizationError < BetterService::Errors::Runtime::RuntimeError
        def initialize(message = "Not authorized", code: :unauthorized, context: {}, original_error: nil)
          super(message, code: code, context: context, original_error: original_error)
        end
      end
    end
  end
end
