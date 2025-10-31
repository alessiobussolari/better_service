# frozen_string_literal: true

require "test_helper"
require "generators/better_service/destroy_generator"

class DestroyGeneratorTest < Rails::Generators::TestCase
  tests BetterService::Generators::DestroyGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  test "generates destroy service file" do
    run_generator ["booking"]

    assert_file "app/services/booking/destroy_service.rb" do |content|
      assert_match(/class Booking::DestroyService < BetterService::DestroyService/, content)
    end
  end

  test "generates service with destroy! in process_with" do
    run_generator ["booking"]

    assert_file "app/services/booking/destroy_service.rb" do |content|
      assert_match(/booking\.destroy!/, content)
    end
  end

  test "generates test file" do
    run_generator ["booking"]

    assert_file "test/services/booking/destroy_service_test.rb"
  end
end
