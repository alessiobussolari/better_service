# frozen_string_literal: true

require "test_helper"
require "generators/better_service/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests BetterService::Generators::InstallGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  test "generates initializer file" do
    run_generator

    assert_file "config/initializers/better_service.rb" do |content|
      assert_match(/BetterService\.configure do \|config\|/, content)
      assert_match(/config\.instrumentation_enabled/, content)
    end
  end

  test "copies locale file" do
    run_generator

    assert_file "config/locales/better_service.en.yml" do |content|
      assert_match(/en:/, content)
      assert_match(/better_service:/, content)
      assert_match(/services:/, content)
      assert_match(/default:/, content)
      assert_match(/created:/, content)
      assert_match(/updated:/, content)
      assert_match(/deleted:/, content)
      assert_match(/listed:/, content)
      assert_match(/shown:/, content)
    end
  end

  test "locale file is valid YAML" do
    run_generator

    assert_file "config/locales/better_service.en.yml" do |content|
      assert_nothing_raised do
        YAML.safe_load(content)
      end
    end
  end

  test "initializer includes all configuration options" do
    run_generator

    assert_file "config/initializers/better_service.rb" do |content|
      # Check for key configuration sections
      assert_match(/instrumentation/, content)
      assert_match(/log_subscriber/, content)
      assert_match(/stats_subscriber/, content)
    end
  end
end
