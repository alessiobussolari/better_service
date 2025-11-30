# frozen_string_literal: true

require "rails_helper"
require "generators/serviceable/action_generator"

RSpec.describe Serviceable::Generators::ActionGenerator, type: :generator do
  tests Serviceable::Generators::ActionGenerator

  describe "generating action service" do
    it "generates action service inheriting from Base" do
      run_generator ["booking", "accept"]

      assert_file "app/services/booking/accept_service.rb" do |content|
        expect(content).to match(/class Booking::AcceptService < BetterService::Services::Base/)
      end
    end

    it "generates service with performed_action declaration" do
      run_generator ["booking", "accept"]

      assert_file "app/services/booking/accept_service.rb" do |content|
        expect(content).to match(/performed_action :accept/)
      end
    end

    it "generates service with required id schema" do
      run_generator ["booking", "publish"]

      assert_file "app/services/booking/publish_service.rb" do |content|
        expect(content).to match(/schema do/)
        expect(content).to match(/required\(:id\)\.filled/)
      end
    end

    it "generates test file with correct name" do
      run_generator ["booking", "reject"]

      assert_file "test/services/booking/reject_service_test.rb" do |content|
        expect(content).to match(/class Booking::RejectServiceTest < ActiveSupport::TestCase/)
      end
    end

    it "action name appears in respond_with message helper" do
      run_generator ["booking", "complete"]

      assert_file "app/services/booking/complete_service.rb" do |content|
        expect(content).to match(/message\("complete\.success"\)/)
      end
    end
  end

  describe "with custom base class" do
    it "generates service with custom base class" do
      run_generator ["booking", "confirm", "--base_class=Booking::BaseService"]

      assert_file "app/services/booking/confirm_service.rb" do |content|
        expect(content).to match(/class Booking::ConfirmService < Booking::BaseService/)
        expect(content).to match(/performed_action :confirm/)
      end
    end

    it "generates service with repository when using base class" do
      run_generator ["booking", "approve", "--base_class=Booking::BaseService"]

      assert_file "app/services/booking/approve_service.rb" do |content|
        expect(content).to match(/booking_repository\.find\(params\[:id\]\)/)
      end
    end
  end

  describe "without base class" do
    it "generates service with user association when not using base class" do
      run_generator ["booking", "cancel"]

      assert_file "app/services/booking/cancel_service.rb" do |content|
        expect(content).to match(/user\.bookings\.find\(params\[:id\]\)/)
      end
    end
  end
end
