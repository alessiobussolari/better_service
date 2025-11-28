# frozen_string_literal: true

require "rails/generators/named_base"

module Serviceable
  module Generators
    class ScaffoldGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :skip_index, type: :boolean, default: false, desc: "Skip Index service generation"
      class_option :skip_show, type: :boolean, default: false, desc: "Skip Show service generation"
      class_option :skip_create, type: :boolean, default: false, desc: "Skip Create service generation"
      class_option :skip_update, type: :boolean, default: false, desc: "Skip Update service generation"
      class_option :skip_destroy, type: :boolean, default: false, desc: "Skip Destroy service generation"
      class_option :presenter, type: :boolean, default: false, desc: "Generate presenter class"
      class_option :skip_repository, type: :boolean, default: false, desc: "Skip repository generation"
      class_option :skip_locale, type: :boolean, default: false, desc: "Skip locale file generation"

      desc "Generate all CRUD services (Index, Show, Create, Update, Destroy) with BaseService"

      def generate_base_service
        say "Generating BaseService, Repository and Locale...", :green
        args = [name]
        args << "--skip_repository" if options[:skip_repository]
        args << "--skip_locale" if options[:skip_locale]
        generate "serviceable:base", *args
      end

      def generate_index_service
        return if options[:skip_index]

        say "Generating Index service...", :green
        generate "serviceable:index", *service_generator_args
      end

      def generate_show_service
        return if options[:skip_show]

        say "Generating Show service...", :green
        generate "serviceable:show", *service_generator_args
      end

      def generate_create_service
        return if options[:skip_create]

        say "Generating Create service...", :green
        generate "serviceable:create", *service_generator_args
      end

      def generate_update_service
        return if options[:skip_update]

        say "Generating Update service...", :green
        generate "serviceable:update", *service_generator_args
      end

      def generate_destroy_service
        return if options[:skip_destroy]

        say "Generating Destroy service...", :green
        generate "serviceable:destroy", *service_generator_args
      end

      def generate_presenter
        return unless options[:presenter]

        say "Generating Presenter...", :green
        generate "better_service:presenter", name
      end

      def show_completion_message
        say "\n" + "=" * 80
        say "Scaffold generation completed! 🎉", :green
        say "=" * 80
        say "\nGenerated base infrastructure:"
        say "  - #{class_name}::BaseService (app/services/#{file_name}/base_service.rb)"
        say "  - #{class_name}Repository (app/repositories/#{file_name}_repository.rb)" unless options[:skip_repository]
        say "  - I18n locale (config/locales/#{file_name}_services.en.yml)" unless options[:skip_locale]
        say "\nGenerated services (inheriting from #{class_name}::BaseService):"
        say "  - #{class_name}::IndexService" unless options[:skip_index]
        say "  - #{class_name}::ShowService" unless options[:skip_show]
        say "  - #{class_name}::CreateService" unless options[:skip_create]
        say "  - #{class_name}::UpdateService" unless options[:skip_update]
        say "  - #{class_name}::DestroyService" unless options[:skip_destroy]
        say "  - #{class_name}Presenter (app/presenters)" if options[:presenter]
        say "\nNext steps:"
        say "  1. Review and customize the generated services"
        say "  2. Update schemas with your specific validations"
        say "  3. Run the tests: rails test test/services/#{file_name}\n\n"
      end

      private

      # Build arguments array for CRUD service generators
      # Always includes --base_class since BaseService is always generated
      def service_generator_args
        [name, "--base_class=#{class_name}::BaseService"]
      end
    end
  end
end
