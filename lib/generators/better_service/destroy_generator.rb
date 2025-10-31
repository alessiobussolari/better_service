# frozen_string_literal: true

require "rails/generators/named_base"

module BetterService
  module Generators
    class DestroyGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Generate a Destroy service for deleting resources"

      def create_service_file
        template "destroy_service.rb.tt", File.join("app/services", class_path, "#{file_name}/destroy_service.rb")
      end

      def create_test_file
        template "service_test.rb.tt", File.join("test/services", class_path, "#{file_name}/destroy_service_test.rb")
      end

      private

      def service_class_name
        "#{class_name}::DestroyService"
      end
    end
  end
end
