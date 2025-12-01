# frozen_string_literal: true

require "rails_helper"
require "generators/better_service/presenter_generator"

RSpec.describe BetterService::Generators::PresenterGenerator, type: :generator do
  tests BetterService::Generators::PresenterGenerator

  describe "generating presenter" do
    it "generates presenter file" do
      run_generator [ "booking" ]

      assert_file "app/presenters/booking_presenter.rb" do |content|
        expect(content).to match(/class BookingPresenter < BetterService::Presenter/)
        expect(content).to match(/def as_json\(opts = {}\)/)
      end
    end

    it "generates test file" do
      run_generator [ "booking" ]

      assert_file "test/presenters/booking_presenter_test.rb" do |content|
        expect(content).to match(/class BookingPresenterTest < ActiveSupport::TestCase/)
        expect(content).to match(/@presenter = BookingPresenter\.new\(@booking\)/)
      end
    end

    it "works without attributes" do
      run_generator [ "booking" ]

      assert_file "app/presenters/booking_presenter.rb" do |content|
        expect(content).to match(/class BookingPresenter < BetterService::Presenter/)
        expect(content).to match(/def as_json/)
      end
    end

    it "includes example methods as comments in presenter" do
      run_generator [ "booking" ]

      assert_file "app/presenters/booking_presenter.rb" do |content|
        expect(content).to match(/# def admin_fields/)
        expect(content).to match(/# def user_can_edit\?/)
        expect(content).to match(/current_user/)
      end
    end

    it "test includes options handling" do
      run_generator [ "booking" ]

      assert_file "test/presenters/booking_presenter_test.rb" do |content|
        expect(content).to match(/test "accepts options"/)
        expect(content).to match(/test "provides access to current_user from options"/)
      end
    end
  end

  describe "with attributes" do
    it "includes attributes in presenter" do
      run_generator [ "booking", "title:string", "price:decimal" ]

      assert_file "app/presenters/booking_presenter.rb" do |content|
        expect(content).to match(/title: object\.title/)
        expect(content).to match(/price: object\.price/)
      end
    end

    it "includes attributes in test" do
      run_generator [ "booking", "title:string", "price:decimal" ]

      assert_file "test/presenters/booking_presenter_test.rb" do |content|
        expect(content).to match(/title: "test_title"/)
        expect(content).to match(/price: "test_price"/)
        expect(content).to match(/assert_equal @booking\.title, json\[:title\]/)
        expect(content).to match(/assert_equal @booking\.price, json\[:price\]/)
      end
    end
  end
end
