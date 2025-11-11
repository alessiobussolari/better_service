# frozen_string_literal: true

require "rails/generators/base"

module BetterService
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Generate BetterService initializer with configuration options"

      def create_initializer_file
        template "better_service_initializer.rb.tt", "config/initializers/better_service.rb"
      end

      def display_readme
        say
        say "BetterService initializer created!", :green
        say
        say "Next steps:", :yellow
        say "  1. Review config/initializers/better_service.rb"
        say "  2. Enable instrumentation if needed"
        say "  3. Configure logging and stats subscribers"
        say
        say "Documentation:", :cyan
        say "  Getting Started: docs/start/getting-started.md"
        say "  Configuration:   docs/start/configuration.md"
        say
      end
    end
  end
end
