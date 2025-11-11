# frozen_string_literal: true

require "test_helper"
require "generators/serviceable/scaffold_generator"

class ScaffoldGeneratorTest < Rails::Generators::TestCase
  tests Serviceable::Generators::ScaffoldGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  test "generates all CRUD services by default" do
    run_generator ["booking"]

    assert_file "app/services/booking/index_service.rb"
    assert_file "app/services/booking/show_service.rb"
    assert_file "app/services/booking/create_service.rb"
    assert_file "app/services/booking/update_service.rb"
    assert_file "app/services/booking/destroy_service.rb"
  end

  test "generates all CRUD test files" do
    run_generator ["booking"]

    assert_file "test/services/booking/index_service_test.rb"
    assert_file "test/services/booking/show_service_test.rb"
    assert_file "test/services/booking/create_service_test.rb"
    assert_file "test/services/booking/update_service_test.rb"
    assert_file "test/services/booking/destroy_service_test.rb"
  end

  test "skips index service when --skip-index is passed" do
    run_generator ["booking", "--skip-index"]

    assert_no_file "app/services/booking/index_service.rb"
    assert_file "app/services/booking/show_service.rb"
    assert_file "app/services/booking/create_service.rb"
  end

  test "skips show service when --skip-show is passed" do
    run_generator ["booking", "--skip-show"]

    assert_file "app/services/booking/index_service.rb"
    assert_no_file "app/services/booking/show_service.rb"
    assert_file "app/services/booking/create_service.rb"
  end

  test "skips create service when --skip-create is passed" do
    run_generator ["booking", "--skip-create"]

    assert_file "app/services/booking/index_service.rb"
    assert_no_file "app/services/booking/create_service.rb"
  end

  test "skips update service when --skip-update is passed" do
    run_generator ["booking", "--skip-update"]

    assert_file "app/services/booking/index_service.rb"
    assert_no_file "app/services/booking/update_service.rb"
  end

  test "skips destroy service when --skip-destroy is passed" do
    run_generator ["booking", "--skip-destroy"]

    assert_file "app/services/booking/index_service.rb"
    assert_no_file "app/services/booking/destroy_service.rb"
  end

  test "can skip multiple services" do
    run_generator ["booking", "--skip-index", "--skip-destroy"]

    assert_no_file "app/services/booking/index_service.rb"
    assert_file "app/services/booking/show_service.rb"
    assert_file "app/services/booking/create_service.rb"
    assert_file "app/services/booking/update_service.rb"
    assert_no_file "app/services/booking/destroy_service.rb"
  end

  test "does not generate presenter by default" do
    run_generator ["booking"]

    assert_no_file "app/presenters/booking_presenter.rb"
    assert_no_file "test/presenters/booking_presenter_test.rb"
  end

  test "generates presenter when --presenter is passed" do
    run_generator ["booking", "--presenter"]

    assert_file "app/presenters/booking_presenter.rb" do |content|
      assert_match(/class BookingPresenter < BetterService::Presenter/, content)
    end

    assert_file "test/presenters/booking_presenter_test.rb" do |content|
      assert_match(/class BookingPresenterTest < ActiveSupport::TestCase/, content)
    end
  end

  test "can combine --presenter with skip options" do
    run_generator ["booking", "--presenter", "--skip-index", "--skip-destroy"]

    assert_file "app/presenters/booking_presenter.rb"
    assert_no_file "app/services/booking/index_service.rb"
    assert_file "app/services/booking/show_service.rb"
    assert_no_file "app/services/booking/destroy_service.rb"
  end
end
