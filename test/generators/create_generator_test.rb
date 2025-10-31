# frozen_string_literal: true

require "test_helper"
require "generators/better_service/create_generator"

class CreateGeneratorTest < Rails::Generators::TestCase
  tests BetterService::Generators::CreateGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  test "generates create service file" do
    run_generator ["booking"]

    assert_file "app/services/booking/create_service.rb" do |content|
      assert_match(/class Booking::CreateService < BetterService::CreateService/, content)
    end
  end

  test "generates service with create! in process_with" do
    run_generator ["booking"]

    assert_file "app/services/booking/create_service.rb" do |content|
      assert_match(/process_with do/, content)
      assert_match(/user\.bookings\.create!\(params\)/, content)
      assert_match(/\{ resource: booking \}/, content)
    end
  end

  test "generates test file" do
    run_generator ["booking"]

    assert_file "test/services/booking/create_service_test.rb"
  end
end
