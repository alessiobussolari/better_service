# frozen_string_literal: true

require "test_helper"
require "generators/serviceable/action_generator"

class ActionGeneratorTest < Rails::Generators::TestCase
  tests Serviceable::Generators::ActionGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  test "generates action service inheriting from Base" do
    run_generator ["booking", "accept"]

    assert_file "app/services/booking/accept_service.rb" do |content|
      assert_match(/class Booking::AcceptService < BetterService::Services::Base/, content)
    end
  end

  test "generates service with _action_name declaration" do
    run_generator ["booking", "accept"]

    assert_file "app/services/booking/accept_service.rb" do |content|
      assert_match(/self\._action_name = :accept/, content)
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

  test "action name appears in respond_with message helper" do
    run_generator ["booking", "complete"]

    assert_file "app/services/booking/complete_service.rb" do |content|
      assert_match(/message\("complete\.success"\)/, content)
    end
  end

  test "generates service with custom base class" do
    run_generator ["booking", "confirm", "--base_class=Booking::BaseService"]

    assert_file "app/services/booking/confirm_service.rb" do |content|
      assert_match(/class Booking::ConfirmService < Booking::BaseService/, content)
      assert_match(/self\._action_name = :confirm/, content)
    end
  end

  test "generates service with repository when using base class" do
    run_generator ["booking", "approve", "--base_class=Booking::BaseService"]

    assert_file "app/services/booking/approve_service.rb" do |content|
      assert_match(/booking_repository\.find\(params\[:id\]\)/, content)
    end
  end

  test "generates service with user association when not using base class" do
    run_generator ["booking", "cancel"]

    assert_file "app/services/booking/cancel_service.rb" do |content|
      assert_match(/user\.bookings\.find\(params\[:id\]\)/, content)
    end
  end
end
