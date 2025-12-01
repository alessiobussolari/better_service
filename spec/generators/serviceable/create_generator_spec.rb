# frozen_string_literal: true

require "rails_helper"
require "generators/serviceable/create_generator"

RSpec.describe Serviceable::Generators::CreateGenerator, type: :generator do
  tests Serviceable::Generators::CreateGenerator

  describe "generating create service" do
    it "generates create service file" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/create_service.rb" do |content|
        expect(content).to match(/class Booking::CreateService < BetterService::Services::Base/)
      end
    end

    it "generates service with performed_action :created" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/create_service.rb" do |content|
        expect(content).to match(/performed_action :created/)
      end
    end

    it "generates service with transaction enabled" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/create_service.rb" do |content|
        expect(content).to match(/with_transaction true/)
      end
    end

    it "generates service with process_with block" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/create_service.rb" do |content|
        expect(content).to match(/process_with do/)
        expect(content).to match(/user\.bookings\.build\(params\)/)
      end
    end

    it "generates test file" do
      run_generator [ "booking" ]

      assert_file "test/services/booking/create_service_test.rb"
    end
  end
end
