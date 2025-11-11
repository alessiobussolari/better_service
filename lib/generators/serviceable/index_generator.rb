# frozen_string_literal: true

require "rails/generators/named_base"

module Serviceable
  module Generators
    class IndexGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Generate an Index service for listing resources"

      def create_service_file
        template "index_service.rb.tt", File.join("app/services", class_path, "#{file_name}/index_service.rb")
      end

      def create_test_file
        template "service_test.rb.tt", File.join("test/services", class_path, "#{file_name}/index_service_test.rb")
      end

      private

      def service_class_name
        "#{class_name}::IndexService"
      end
    end
  end
end
