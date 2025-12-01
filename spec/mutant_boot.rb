# frozen_string_literal: true

# Boot file for Mutant mutation testing
# This file loads the Rails environment without the full RSpec setup

# Add spec directory to load path for spec_helper
$LOAD_PATH.unshift(File.expand_path(".", __dir__))

# Load the Rails test application
ENV["RAILS_ENV"] ||= "test"
require_relative "rails_app/config/environment"

# Require BetterService after Rails is loaded
require "better_service"
