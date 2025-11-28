# frozen_string_literal: true

require "rails/generators/named_base"

module Serviceable
  module Generators
    # BaseGenerator - Generate a base service class for a resource namespace
    #
    # Creates a ResourceBaseService that centralizes:
    # - Repository initialization via RepositoryAware concern
    # - Cache configuration
    # - Messages namespace (I18n)
    # - Presenter configuration
    #
    # Usage:
    #   rails generate serviceable:base Articles
    #   rails generate serviceable:base Admin::Articles
    #   rails generate serviceable:base Articles --skip_repository
    #   rails generate serviceable:base Articles --skip_locale
    #
    # This generates:
    #   app/services/articles/base_service.rb
    #   app/repositories/articles_repository.rb
    #   config/locales/articles_services.en.yml
    #   test/services/articles/base_service_test.rb
    #   test/repositories/articles_repository_test.rb
    class BaseGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Generate a base service with repository, cache, and I18n configuration"

      class_option :skip_repository, type: :boolean, default: false,
                   desc: "Skip repository generation"
      class_option :skip_locale, type: :boolean, default: false,
                   desc: "Skip locale file generation"
      class_option :skip_presenter, type: :boolean, default: false,
                   desc: "Skip presenter configuration in base service"
      class_option :skip_test, type: :boolean, default: false,
                   desc: "Skip test file generation"

      def create_base_service
        template "base_service.rb.tt",
                 File.join("app/services", class_path, file_name, "base_service.rb")
      end

      def create_repository
        return if options[:skip_repository]

        template "repository.rb.tt",
                 File.join("app/repositories", class_path, "#{file_name}_repository.rb")
      end

      def create_locale
        return if options[:skip_locale]

        template "base_locale.en.yml.tt",
                 File.join("config/locales", "#{file_name}_services.en.yml")
      end

      def create_base_service_test
        return if options[:skip_test]

        template "base_service_test.rb.tt",
                 File.join("test/services", class_path, file_name, "base_service_test.rb")
      end

      def create_repository_test
        return if options[:skip_test] || options[:skip_repository]

        template "repository_test.rb.tt",
                 File.join("test/repositories", class_path, "#{file_name}_repository_test.rb")
      end

      def show_completion_message
        say "\n" + "=" * 80
        say "Base service generation completed! 🎉", :green
        say "=" * 80
        say "\nGenerated files:"
        say "  - #{class_name}::BaseService (app/services/#{file_path}/base_service.rb)"
        say "  - #{class_name}Repository (app/repositories/#{file_path}_repository.rb)" unless options[:skip_repository]
        say "  - I18n locale (config/locales/#{file_name}_services.en.yml)" unless options[:skip_locale]
        say "\nNext steps:"
        say "  1. Customize the base service with resource-specific methods"
        say "  2. Add custom repository methods for your queries"
        say "  3. Generate CRUD services that inherit from BaseService:"
        say "     rails generate serviceable:scaffold #{name} --base"
        say "\nServices will inherit like: #{class_name}::IndexService < #{class_name}::BaseService\n\n"
      end

      private

      def file_path
        File.join(class_path, file_name)
      end

      def repository_class_name
        "#{class_name}Repository"
      end

      def presenter_class_name
        "#{class_name}Presenter"
      end

      def base_service_class_name
        "#{class_name}::BaseService"
      end
    end
  end
end
