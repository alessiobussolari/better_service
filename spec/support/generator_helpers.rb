# frozen_string_literal: true

require "fileutils"
require "rails/generators"
require "rails/generators/actions"
require "rails/generators/testing/behavior"
require "rails/generators/testing/assertions"
require "minitest/assertions"
require "active_support/testing/assertions"

# Helper methods for generator specs
# Note: Generator testing modules are loaded lazily only when needed
module GeneratorHelpers
  extend ActiveSupport::Concern

  included do
    include FileUtils
    include Minitest::Assertions
    include ActiveSupport::Testing::Assertions
    include Rails::Generators::Testing::Behavior
    include Rails::Generators::Testing::Assertions

    # Minitest assertions requires this
    attr_accessor :assertions

    # Initialize assertions counter for minitest compatibility
    before do
      self.assertions = 0
    end

    # Set destination for generated files
    destination File.expand_path("../../tmp", __dir__)

    before do
      prepare_destination
    end

    after do
      FileUtils.rm_rf(destination_root) if File.exist?(destination_root)
    end
  end

  # Returns the path to a generated file
  def file(relative_path)
    File.join(destination_root, relative_path)
  end

  # Checks if a file exists
  def file_exists?(relative_path)
    File.exist?(file(relative_path))
  end

  # Reads the content of a generated file
  def file_content(relative_path)
    File.read(file(relative_path))
  end

  # Checks if a file contains specific content
  def file_contains?(relative_path, content)
    return false unless file_exists?(relative_path)

    file_content(relative_path).include?(content)
  end
end

RSpec.configure do |config|
  config.include GeneratorHelpers, type: :generator
end
