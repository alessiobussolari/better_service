# frozen_string_literal: true

require "rails_helper"
require "generators/serviceable/show_generator"

RSpec.describe Serviceable::Generators::ShowGenerator, type: :generator do
  tests Serviceable::Generators::ShowGenerator

  describe "generating show service" do
    it "generates show service file" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/show_service.rb" do |content|
        expect(content).to match(/class Booking::ShowService < BetterService::Services::Base/)
        expect(content).to match(/frozen_string_literal: true/)
      end
    end

    it "generates service with performed_action :showed" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/show_service.rb" do |content|
        expect(content).to match(/performed_action :showed/)
      end
    end

    it "generates service with required id schema" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/show_service.rb" do |content|
        expect(content).to match(/schema do/)
        expect(content).to match(/required\(:id\)\.filled/)
      end
    end

    it "generates service with find in search_with" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/show_service.rb" do |content|
        expect(content).to match(/search_with do/)
        expect(content).to match(/user\.bookings\.find\(params\[:id\]\)/)
      end
    end

    it "generates test file" do
      run_generator [ "booking" ]

      assert_file "test/services/booking/show_service_test.rb" do |content|
        expect(content).to match(/class Booking::ShowServiceTest < ActiveSupport::TestCase/)
      end
    end
  end
end
