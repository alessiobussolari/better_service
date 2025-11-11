# frozen_string_literal: true

module BetterService
  module Errors
    module Workflowable
      module Configuration
        # Raised when a workflow has duplicate step names
        #
        # Each step in a workflow must have a unique name. This error is raised
        # if you try to define multiple steps with the same name.
        #
        # @example Duplicate step names
        #   class MyWorkflow < BetterService::Workflow
        #     step :create_user,
        #          with: User::CreateService
        #
        #     step :create_user,  # Duplicate name!
        #          with: Profile::CreateService
        #   end
        #
        #   # => raises DuplicateStepError during class definition
        class DuplicateStepError < WorkflowConfigurationError
        end
      end
    end
  end
end
