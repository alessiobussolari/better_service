# frozen_string_literal: true

require "rails/generators/named_base"

module BetterService
  module Generators
    # LocaleGenerator - Generate I18n locale files for BetterService
    #
    # Usage:
    #   rails generate better_service:locale products
    #   rails generate better_service:locale bookings
    #
    # This generates config/locales/products_services.en.yml with scaffolded
    # translations for common service actions (create, update, destroy, etc.)
    class LocaleGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Generate I18n locale file for BetterService messages"

      # Optional: specify which actions to include
      class_option :actions,
                   type: :array,
                   default: %w[create update destroy index show],
                   desc: "Actions to include in locale file"

      def create_locale_file
        template "locale.en.yml.tt", "config/locales/#{file_name.pluralize}_services.en.yml"
      end

      def display_info
        say
        say "Locale file created: config/locales/#{file_name.pluralize}_services.en.yml", :green
        say
        say "Usage in services:", :yellow
        say "  class #{class_name.pluralize}::CreateService < CreateService"
        say "    messages_namespace :#{file_name.pluralize}"
        say "  end"
        say
        say "Then customize the messages in the locale file to your needs.", :cyan
        say
      end

      private

      def plural_name
        file_name.pluralize
      end

      def actions_list
        options[:actions]
      end
    end
  end
end
