# frozen_string_literal: true

require "rails/generators/named_base"

module BetterService
  module Generators
    class ScaffoldGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :skip_index, type: :boolean, default: false, desc: "Skip Index service generation"
      class_option :skip_show, type: :boolean, default: false, desc: "Skip Show service generation"
      class_option :skip_create, type: :boolean, default: false, desc: "Skip Create service generation"
      class_option :skip_update, type: :boolean, default: false, desc: "Skip Update service generation"
      class_option :skip_destroy, type: :boolean, default: false, desc: "Skip Destroy service generation"

      desc "Generate all CRUD services (Index, Show, Create, Update, Destroy)"

      def generate_index_service
        return if options[:skip_index]

        say "Generating Index service...", :green
        generate "better_service:index", name
      end

      def generate_show_service
        return if options[:skip_show]

        say "Generating Show service...", :green
        generate "better_service:show", name
      end

      def generate_create_service
        return if options[:skip_create]

        say "Generating Create service...", :green
        generate "better_service:create", name
      end

      def generate_update_service
        return if options[:skip_update]

        say "Generating Update service...", :green
        generate "better_service:update", name
      end

      def generate_destroy_service
        return if options[:skip_destroy]

        say "Generating Destroy service...", :green
        generate "better_service:destroy", name
      end

      def show_completion_message
        say "\n" + "=" * 80
        say "Scaffold generation completed! 🎉", :green
        say "=" * 80
        say "\nGenerated services:"
        say "  - #{class_name}::IndexService" unless options[:skip_index]
        say "  - #{class_name}::ShowService" unless options[:skip_show]
        say "  - #{class_name}::CreateService" unless options[:skip_create]
        say "  - #{class_name}::UpdateService" unless options[:skip_update]
        say "  - #{class_name}::DestroyService" unless options[:skip_destroy]
        say "\nNext steps:"
        say "  1. Review and customize the generated services"
        say "  2. Update schemas with your specific validations"
        say "  3. Run the tests: rails test test/services/#{file_name}\n\n"
      end
    end
  end
end
