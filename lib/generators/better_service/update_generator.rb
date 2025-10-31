# frozen_string_literal: true

require "rails/generators/named_base"

module BetterService
  module Generators
    class UpdateGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Generate an Update service for modifying resources"

      def create_service_file
        template "update_service.rb.tt", File.join("app/services", class_path, "#{file_name}/update_service.rb")
      end

      def create_test_file
        template "service_test.rb.tt", File.join("test/services", class_path, "#{file_name}/update_service_test.rb")
      end

      private

      def service_class_name
        "#{class_name}::UpdateService"
      end
    end
  end
end
