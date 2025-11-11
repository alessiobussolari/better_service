# frozen_string_literal: true

require "test_helper"
require "generators/serviceable/index_generator"

class IndexGeneratorTest < Rails::Generators::TestCase
  tests Serviceable::Generators::IndexGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  test "generates index service file" do
    run_generator ["booking"]

    assert_file "app/services/booking/index_service.rb" do |content|
      assert_match(/class Booking::IndexService < BetterService::IndexService/, content)
      assert_match(/frozen_string_literal: true/, content)
    end
  end

  test "generates service with schema" do
    run_generator ["booking"]

    assert_file "app/services/booking/index_service.rb" do |content|
      assert_match(/schema do/, content)
      assert_match(/optional\(:page\)/, content)
      assert_match(/optional\(:per_page\)/, content)
      assert_match(/optional\(:search\)/, content)
    end
  end

  test "generates service with search_with block" do
    run_generator ["booking"]

    assert_file "app/services/booking/index_service.rb" do |content|
      assert_match(/search_with do/, content)
      assert_match(/bookings = user\.bookings/, content)
      assert_match(/\{ items: bookings\.to_a \}/, content)
    end
  end

  test "generates service with process_with block including metadata" do
    run_generator ["booking"]

    assert_file "app/services/booking/index_service.rb" do |content|
      assert_match(/process_with do \|data\|/, content)
      assert_match(/metadata:/, content)
      assert_match(/stats:/, content)
      assert_match(/pagination:/, content)
    end
  end

  test "generates service with respond_with block" do
    run_generator ["booking"]

    assert_file "app/services/booking/index_service.rb" do |content|
      assert_match(/respond_with do \|data\|/, content)
      assert_match(/success_result/, content)
    end
  end

  test "generates test file" do
    run_generator ["booking"]

    assert_file "test/services/booking/index_service_test.rb" do |content|
      assert_match(/class Booking::IndexServiceTest < ActiveSupport::TestCase/, content)
      assert_match(/def setup/, content)
    end
  end

  test "handles namespaced models" do
    run_generator ["admin/booking"]

    assert_file "app/services/admin/booking/index_service.rb" do |content|
      assert_match(/class Admin::Booking::IndexService < BetterService::IndexService/, content)
    end
  end
end
