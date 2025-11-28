# frozen_string_literal: true

require "rails/generators/named_base"

module Serviceable
  module Generators
    class IndexGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Generate an Index service for listing resources"

      class_option :base_class, type: :string, default: nil,
                   desc: "Custom base class to inherit from (e.g., Articles::BaseService)"

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

      def parent_class
        options[:base_class] || "BetterService::Services::IndexService"
      end

      def using_base_service?
        options[:base_class].present?
      end
    end
  end
end
