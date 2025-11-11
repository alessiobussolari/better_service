# frozen_string_literal: true

module BetterService
  module Workflows
    # TransactionSupport - Handles database transaction wrapping for workflows
    #
    # This module provides the ability to execute workflows within a database
    # transaction, with automatic rollback on failure.
    module TransactionSupport
      private

      # Execute workflow with transaction wrapper
      #
      # Wraps the workflow execution in an ActiveRecord transaction. If the
      # workflow fails (returns success: false), triggers a rollback.
      #
      # @return [Hash] Result from execute_workflow
      def execute_with_transaction
        result = nil
        ActiveRecord::Base.transaction do
          result = execute_workflow
          # If workflow failed, raise to trigger rollback
          raise ActiveRecord::Rollback if result[:success] == false
        end
        result
      rescue ActiveRecord::Rollback
        # Rollback was triggered, result already contains failure
        result
      end
    end
  end
end
