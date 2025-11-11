# frozen_string_literal: true

require "rails/generators/named_base"

module Workflowable
  module Generators
    class WorkflowGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Generate a Workflow for composing multiple services into a pipeline"

      class_option :steps,
                   type: :array,
                   default: [],
                   desc: "List of step names to include in the workflow (e.g., --steps create_order charge_payment send_email)"

      class_option :transaction,
                   type: :boolean,
                   default: false,
                   desc: "Enable database transactions for the workflow"

      class_option :skip_test,
                   type: :boolean,
                   default: false,
                   desc: "Skip test file generation"

      def create_workflow_file
        template "workflow.rb.tt", File.join("app/workflows", class_path, "#{workflow_file_name}.rb")
      end

      def create_test_file
        return if options[:skip_test]

        template "workflow_test.rb.tt", File.join("test/workflows", class_path, "#{workflow_file_name}_test.rb")
      end

      def show_readme
        readme "WORKFLOW_README" if behavior == :invoke
      end

      private

      def workflow_file_name
        "#{file_name}_workflow"
      end

      def workflow_class_name
        "#{class_name}Workflow"
      end

      def workflow_steps
        @workflow_steps ||= options[:steps].map(&:underscore).map(&:to_sym)
      end

      def use_transaction
        options[:transaction]
      end
    end
  end
end
