# frozen_string_literal: true

require "test_helper"
require "generators/serviceable/update_generator"

class UpdateGeneratorTest < Rails::Generators::TestCase
  tests Serviceable::Generators::UpdateGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  test "generates update service file" do
    run_generator ["booking"]

    assert_file "app/services/booking/update_service.rb" do |content|
      assert_match(/class Booking::UpdateService < BetterService::UpdateService/, content)
    end
  end

  test "generates service with update! in process_with" do
    run_generator ["booking"]

    assert_file "app/services/booking/update_service.rb" do |content|
      assert_match(/booking\.update!\(params\.except\(:id\)\)/, content)
    end
  end

  test "generates test file" do
    run_generator ["booking"]

    assert_file "test/services/booking/update_service_test.rb"
  end
end
