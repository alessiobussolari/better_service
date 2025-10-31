# frozen_string_literal: true

module BetterService
  module Concerns
    module Transactional
      extend ActiveSupport::Concern

      included do
        class_attribute :_with_transaction, default: false
      end

      # Hook for prepend (same as included but triggered by prepend)
      def self.prepended(base)
        base.class_attribute :_with_transaction, default: false
        base.extend(ClassMethods)
      end

      module ClassMethods
      # Enable or disable database transactions for this service
      #
      # @param value [Boolean] whether to wrap process in a transaction
      #
      # @example Enable transactions
      #   class Booking::CreateService < BetterService::CreateService
      #     with_transaction true
      #   end
      #
      # @example Disable transactions
      #   class Booking::ImportService < BetterService::CreateService
      #     with_transaction false  # Disable inherited transaction
      #   end
        def with_transaction(value)
          self._with_transaction = value
        end
      end

      # Override process to wrap in transaction if enabled
      def process(data)
        return super(data) unless self.class._with_transaction

        result = nil
        ActiveRecord::Base.transaction do
          result = super(data)
        end
        result
      end
    end
  end
end
