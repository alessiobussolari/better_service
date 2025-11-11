# frozen_string_literal: true

require "test_helper"
require "generators/serviceable/action_generator"

class ActionGeneratorTest < Rails::Generators::TestCase
  tests Serviceable::Generators::ActionGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  test "generates action service with dynamic name" do
    run_generator ["booking", "accept"]

    assert_file "app/services/booking/accept_service.rb" do |content|
      assert_match(/class Booking::AcceptService < BetterService::ActionService/, content)
    end
  end

  test "generates service with action_name declaration" do
    run_generator ["booking", "accept"]

    assert_file "app/services/booking/accept_service.rb" do |content|
      assert_match(/action_name :accept/, content)
    end
  end

  test "generates service with required id schema" do
    run_generator ["booking", "publish"]

    assert_file "app/services/booking/publish_service.rb" do |content|
      assert_match(/schema do/, content)
      assert_match(/required\(:id\)\.filled/, content)
    end
  end

  test "generates test file with correct name" do
    run_generator ["booking", "reject"]

    assert_file "test/services/booking/reject_service_test.rb" do |content|
      assert_match(/class Booking::RejectServiceTest < ActiveSupport::TestCase/, content)
    end
  end

  test "action name appears in success message" do
    run_generator ["booking", "complete"]

    assert_file "app/services/booking/complete_service.rb" do |content|
      assert_match(/Booking complete successfully/, content)
    end
  end
end
