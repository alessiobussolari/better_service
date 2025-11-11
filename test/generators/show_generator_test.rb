# frozen_string_literal: true

require "test_helper"
require "generators/serviceable/show_generator"

class ShowGeneratorTest < Rails::Generators::TestCase
  tests Serviceable::Generators::ShowGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  test "generates show service file" do
    run_generator ["booking"]

    assert_file "app/services/booking/show_service.rb" do |content|
      assert_match(/class Booking::ShowService < BetterService::ShowService/, content)
      assert_match(/frozen_string_literal: true/, content)
    end
  end

  test "generates service with required id schema" do
    run_generator ["booking"]

    assert_file "app/services/booking/show_service.rb" do |content|
      assert_match(/schema do/, content)
      assert_match(/required\(:id\)\.filled/, content)
    end
  end

  test "generates service with find in search_with" do
    run_generator ["booking"]

    assert_file "app/services/booking/show_service.rb" do |content|
      assert_match(/search_with do/, content)
      assert_match(/user\.bookings\.find\(params\[:id\]\)/, content)
      assert_match(/\{ resource:/, content)
    end
  end

  test "generates test file" do
    run_generator ["booking"]

    assert_file "test/services/booking/show_service_test.rb" do |content|
      assert_match(/class Booking::ShowServiceTest < ActiveSupport::TestCase/, content)
    end
  end
end
