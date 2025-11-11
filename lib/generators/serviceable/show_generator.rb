# frozen_string_literal: true

require "rails/generators/named_base"

module Serviceable
  module Generators
    class ShowGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Generate a Show service for displaying a single resource"

      def create_service_file
        template "show_service.rb.tt", File.join("app/services", class_path, "#{file_name}/show_service.rb")
      end

      def create_test_file
        template "service_test.rb.tt", File.join("test/services", class_path, "#{file_name}/show_service_test.rb")
      end

      private

      def service_class_name
        "#{class_name}::ShowService"
      end
    end
  end
end
