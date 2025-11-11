# frozen_string_literal: true

require "test_helper"
require "generators/better_service/presenter_generator"

class PresenterGeneratorTest < Rails::Generators::TestCase
  tests BetterService::Generators::PresenterGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  test "generates presenter file" do
    run_generator ["booking"]

    assert_file "app/presenters/booking_presenter.rb" do |content|
      assert_match(/class BookingPresenter < BetterService::Presenter/, content)
      assert_match(/def as_json\(opts = {}\)/, content)
    end
  end

  test "generates test file" do
    run_generator ["booking"]

    assert_file "test/presenters/booking_presenter_test.rb" do |content|
      assert_match(/class BookingPresenterTest < ActiveSupport::TestCase/, content)
      assert_match(/@presenter = BookingPresenter\.new\(@booking\)/, content)
    end
  end

  test "includes attributes in presenter" do
    run_generator ["booking", "title:string", "price:decimal"]

    assert_file "app/presenters/booking_presenter.rb" do |content|
      assert_match(/title: object\.title/, content)
      assert_match(/price: object\.price/, content)
    end
  end

  test "includes attributes in test" do
    run_generator ["booking", "title:string", "price:decimal"]

    assert_file "test/presenters/booking_presenter_test.rb" do |content|
      assert_match(/title: "test_title"/, content)
      assert_match(/price: "test_price"/, content)
      assert_match(/assert_equal @booking\.title, json\[:title\]/, content)
      assert_match(/assert_equal @booking\.price, json\[:price\]/, content)
    end
  end

  test "works without attributes" do
    run_generator ["booking"]

    assert_file "app/presenters/booking_presenter.rb" do |content|
      assert_match(/class BookingPresenter < BetterService::Presenter/, content)
      # Should still have the basic structure
      assert_match(/def as_json/, content)
    end
  end

  test "includes example methods as comments in presenter" do
    run_generator ["booking"]

    assert_file "app/presenters/booking_presenter.rb" do |content|
      assert_match(/# def admin_fields/, content)
      assert_match(/# def user_can_edit\?/, content)
      assert_match(/current_user/, content) # Referenced in examples
    end
  end

  test "test includes options handling" do
    run_generator ["booking"]

    assert_file "test/presenters/booking_presenter_test.rb" do |content|
      assert_match(/test "accepts options"/, content)
      assert_match(/test "provides access to current_user from options"/, content)
    end
  end
end
