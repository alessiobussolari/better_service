# frozen_string_literal: true

module BetterService
  # Presenter - Base class for presenting service data
  #
  # Presenters transform raw model data into view-friendly formats.
  # They are typically used with the Presentable concern's presenter DSL.
  #
  # Example:
  #   class ProductPresenter < BetterService::Presenter
  #     def as_json(opts = {})
  #       {
  #         id: object.id,
  #         name: object.name,
  #         price_formatted: "$#{object.price}",
  #         available: object.stock > 0,
  #         # Conditional fields based on current user
  #         **(admin_fields if current_user&.admin?)
  #       }
  #     end
  #
  #     private
  #
  #     def admin_fields
  #       {
  #         cost: object.cost,
  #         margin: object.price - object.cost
  #       }
  #     end
  #   end
  #
  # Usage with services:
  #   class Products::IndexService < IndexService
  #     presenter ProductPresenter
  #
  #     presenter_options do
  #       { current_user: user }
  #     end
  #
  #     search_with do
  #       { items: Product.all.to_a }
  #     end
  #   end
  class Presenter
    attr_reader :object, :options

    # Initialize presenter
    #
    # @param object [Object] The object to present (e.g., ActiveRecord model)
    # @param options [Hash] Additional options (e.g., current_user, permissions)
    def initialize(object, **options)
      @object = object
      @options = options
    end

    # Override in subclass to define JSON representation
    #
    # @param opts [Hash] JSON serialization options
    # @return [Hash] Hash representation of the object
    def as_json(opts = {})
      # Default implementation delegates to object
      if object.respond_to?(:as_json)
        object.as_json(opts)
      else
        { data: object }
      end
    end

    # JSON string representation
    #
    # @param opts [Hash] JSON serialization options
    # @return [String] JSON string
    def to_json(opts = {})
      as_json(opts).to_json
    end

    # Hash representation (alias for as_json)
    #
    # @return [Hash] Hash representation
    def to_h
      as_json
    end

    private

    # Get current user from options
    #
    # @return [Object, nil] Current user if provided in options
    def current_user
      options[:current_user]
    end

    # Check if a field should be included based on options
    #
    # Useful for selective field rendering based on client requests.
    #
    # @param field [Symbol, String] Field name to check
    # @return [Boolean] Whether field should be included
    #
    # @example
    #   # In service:
    #   presenter_options do
    #     { fields: params[:fields]&.split(',')&.map(&:to_sym) }
    #   end
    #
    #   # In presenter:
    #   def as_json(opts = {})
    #     {
    #       id: object.id,
    #       name: object.name,
    #       **(expensive_data if include_field?(:details))
    #     }
    #   end
    def include_field?(field)
      return true unless options[:fields]

      options[:fields].include?(field.to_sym)
    end

    # Check if current user has a specific role/permission
    #
    # @param role [Symbol, String] Role to check
    # @return [Boolean] Whether user has the role
    def user_can?(role)
      return false unless current_user
      return false unless current_user.respond_to?(:has_role?)

      current_user.has_role?(role)
    end
  end
end
