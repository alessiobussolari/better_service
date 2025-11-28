# frozen_string_literal: true

module BetterService
  module Concerns
    module Serviceable
      # RepositoryAware - DSL for declaring repository dependencies in services
      #
      # This concern provides a clean way to declare repository dependencies
      # in service classes, promoting the repository pattern and enforcing
      # separation between business logic and data access.
      #
      # @example Basic usage
      #   class Products::CreateService < Products::BaseService
      #     include BetterService::Concerns::Serviceable::RepositoryAware
      #
      #     performed_action :created
      #     with_transaction true
      #
      #     repository :product
      #
      #     process_with do |data|
      #       { resource: product_repository.create!(params) }
      #     end
      #   end
      #
      # @example With custom class name
      #   class Bookings::AcceptService < Bookings::BaseService
      #     include BetterService::Concerns::Serviceable::RepositoryAware
      #
      #     repository :booking, class_name: "Bookings::BookingRepository"
      #     repository :user, class_name: "Users::UserRepository", as: :user_repo
      #
      #     search_with do
      #       { booking: booking_repository.search({ id_eq: params[:id] }, limit: 1) }
      #     end
      #   end
      #
      # @example Multiple repositories shorthand
      #   class Dashboard::IndexService < Dashboard::BaseService
      #     include BetterService::Concerns::Serviceable::RepositoryAware
      #
      #     performed_action :listed
      #
      #     repositories :user, :booking, :payment
      #   end
      #
      module RepositoryAware
        extend ActiveSupport::Concern

        class_methods do
          # Declare a repository dependency
          #
          # Creates a memoized private accessor method for the repository.
          #
          # @param name [Symbol] Base name for the repository
          # @param class_name [String, nil] Full class name of the repository
          #   If nil, derives from name: :product -> "ProductRepository"
          # @param as [Symbol, nil] Custom accessor name
          #   If nil, uses "#{name}_repository"
          # @return [void]
          #
          # @example Standard naming
          #   repository :product  # -> product_repository -> ProductRepository
          #
          # @example Custom class
          #   repository :booking, class_name: "Bookings::BookingRepository"
          #
          # @example Custom accessor
          #   repository :user, as: :users  # -> users -> UserRepository
          def repository(name, class_name: nil, as: nil)
            accessor_name = as || "#{name}_repository"
            repo_class_name = class_name || "#{name.to_s.camelize}Repository"

            define_method(accessor_name) do
              ivar = "@#{accessor_name}"
              instance_variable_get(ivar) || begin
                klass = repo_class_name.constantize
                instance_variable_set(ivar, klass.new)
              end
            end

            private accessor_name
          end

          # Declare multiple repository dependencies
          #
          # Shorthand for declaring multiple repositories with standard naming.
          #
          # @param names [Array<Symbol>] Repository names
          # @return [void]
          #
          # @example
          #   repositories :user, :booking, :payment
          #   # Equivalent to:
          #   # repository :user
          #   # repository :booking
          #   # repository :payment
          def repositories(*names)
            names.each { |name| repository(name) }
          end
        end
      end
    end
  end
end
