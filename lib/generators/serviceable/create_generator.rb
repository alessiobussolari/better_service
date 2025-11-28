# frozen_string_literal: true

require "rails/generators/named_base"

module Serviceable
  module Generators
    class CreateGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Generate a Create service for creating new resources"

      class_option :base_class, type: :string, default: nil,
                   desc: "Custom base class to inherit from (e.g., Articles::BaseService)"

      def create_service_file
        template "create_service.rb.tt", File.join("app/services", class_path, "#{file_name}/create_service.rb")
      end

      def create_test_file
        template "service_test.rb.tt", File.join("test/services", class_path, "#{file_name}/create_service_test.rb")
      end

      private

      def service_class_name
        "#{class_name}::CreateService"
      end

      def parent_class
        options[:base_class] || "BetterService::Services::Base"
      end

      def using_base_service?
        options[:base_class].present?
      end
    end
  end
end
