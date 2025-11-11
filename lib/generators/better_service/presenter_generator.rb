# frozen_string_literal: true

require "rails/generators/named_base"

module BetterService
  module Generators
    # PresenterGenerator - Generate presenter classes for BetterService
    #
    # Usage:
    #   rails generate better_service:presenter Product
    #   rails generate better_service:presenter Product name:string price:decimal
    #
    # This generates:
    #   - app/presenters/product_presenter.rb
    #   - test/presenters/product_presenter_test.rb
    class PresenterGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Generate a presenter class for BetterService"

      argument :attributes, type: :array, default: [], banner: "field:type field:type"

      def create_presenter_file
        template "presenter.rb.tt", File.join("app/presenters", class_path, "#{file_name}_presenter.rb")
      end

      def create_test_file
        template "presenter_test.rb.tt", File.join("test/presenters", class_path, "#{file_name}_presenter_test.rb")
      end

      def display_info
        say
        say "Presenter created: app/presenters/#{file_name}_presenter.rb", :green
        say "Test created: test/presenters/#{file_name}_presenter_test.rb", :green
        say
        say "Usage in services:", :yellow
        say "  class #{class_name.pluralize}::IndexService < IndexService"
        say "    presenter #{class_name}Presenter"
        say
        say "    presenter_options do"
        say "      { current_user: user }"
        say "    end"
        say "  end"
        say
        say "Customize the as_json method in the presenter to format your data.", :cyan
        say
      end

      private

      def presenter_class_name
        "#{class_name}Presenter"
      end

      def attributes_list
        attributes.map(&:name)
      end
    end
  end
end
