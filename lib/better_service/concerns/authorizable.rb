# frozen_string_literal: true

module BetterService
  module Concerns
    # Authorizable adds authorization support to services.
    #
    # Use the `authorize_with` DSL to define authorization logic that runs
    # BEFORE the search phase (fail fast principle).
    #
    # The authorization block has access to:
    # - user: The current user object
    # - params: The validated parameters
    #
    # If authorization fails (block returns false/nil), the service stops
    # immediately and returns an error result with code :unauthorized.
    #
    # Example:
    #   class Product::UpdateService < BetterService::UpdateService
    #     authorize_with do
    #       user.admin? || product_belongs_to_user?
    #     end
    #
    #     def product_belongs_to_user?
    #       Product.find(params[:id]).user_id == user.id
    #     end
    #   end
    #
    # Works with any authorization library (Pundit, CanCanCan, custom):
    #
    #   # Pundit style
    #   authorize_with do
    #     ProductPolicy.new(user, resource).update?
    #   end
    #
    #   # CanCanCan style
    #   authorize_with do
    #     Ability.new(user).can?(:update, :product)
    #   end
    #
    #   # Custom logic
    #   authorize_with do
    #     user.has_role?(:editor) && params[:status] != 'published'
    #   end
    module Authorizable
      extend ActiveSupport::Concern

      included do
        class_attribute :_authorize_block, default: nil
      end

      class_methods do
        # Define authorization logic that runs before search phase.
        #
        # @yield Block that returns true/false for authorization check
        # @return [void]
        #
        # @example Simple role check
        #   authorize_with do
        #     user.admin?
        #   end
        #
        # @example Resource ownership check
        #   authorize_with do
        #     resource = Product.find(params[:id])
        #     resource.user_id == user.id
        #   end
        #
        # @example With Pundit
        #   authorize_with do
        #     ProductPolicy.new(user, Product.find(params[:id])).update?
        #   end
        def authorize_with(&block)
          self._authorize_block = block
        end
      end

      # Execute authorization check if defined.
      #
      # Runs the authorization block defined with `authorize_with`.
      # Has access to user and params.
      #
      # @return [Hash, nil] Returns error_result if authorization fails, nil if passes
      def authorize!
        return nil unless self.class._authorize_block

        authorized = instance_exec(&self.class._authorize_block)

        return nil if authorized

        error_result("Not authorized to perform this action", code: :unauthorized)
      end
    end
  end
end
