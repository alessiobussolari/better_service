# frozen_string_literal: true

require "test_helper"
require "generators/better_service/locale_generator"

class LocaleGeneratorTest < Rails::Generators::TestCase
  tests BetterService::Generators::LocaleGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  test "generates locale file with default actions" do
    run_generator ["booking"]

    assert_file "config/locales/bookings_services.en.yml" do |content|
      assert_match(/en:/, content)
      assert_match(/bookings:/, content)
      assert_match(/services:/, content)
      assert_match(/create:/, content)
      assert_match(/update:/, content)
      assert_match(/destroy:/, content)
      assert_match(/index:/, content)
      assert_match(/show:/, content)
    end
  end

  test "generates locale file with custom actions" do
    run_generator ["booking", "--actions=publish", "archive"]

    assert_file "config/locales/bookings_services.en.yml" do |content|
      assert_match(/publish:/, content)
      assert_match(/archive:/, content)
    end
  end

  test "uses pluralized file name" do
    run_generator ["user"]

    assert_file "config/locales/users_services.en.yml"
  end

  test "generates valid YAML structure" do
    run_generator ["booking"]

    assert_file "config/locales/bookings_services.en.yml" do |content|
      # Should be parseable as YAML
      assert_nothing_raised do
        YAML.safe_load(content)
      end
    end
  end

  test "includes success and failure messages for each action" do
    run_generator ["booking"]

    assert_file "config/locales/bookings_services.en.yml" do |content|
      assert_match(/success:/, content)
      assert_match(/failure:/, content)
    end
  end
end
