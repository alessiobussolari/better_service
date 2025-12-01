# frozen_string_literal: true

require "rails_helper"
require "generators/serviceable/destroy_generator"

RSpec.describe Serviceable::Generators::DestroyGenerator, type: :generator do
  tests Serviceable::Generators::DestroyGenerator

  describe "generating destroy service" do
    it "generates destroy service file" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/destroy_service.rb" do |content|
        expect(content).to match(/class Booking::DestroyService < BetterService::Services::Base/)
      end
    end

    it "generates service with performed_action :destroyed" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/destroy_service.rb" do |content|
        expect(content).to match(/performed_action :destroyed/)
      end
    end

    it "generates service with transaction enabled" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/destroy_service.rb" do |content|
        expect(content).to match(/with_transaction true/)
      end
    end

    it "generates service with destroy in process_with" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/destroy_service.rb" do |content|
        expect(content).to match(/process_with do/)
        expect(content).to match(/record\.destroy!/)
      end
    end

    it "generates test file" do
      run_generator [ "booking" ]

      assert_file "test/services/booking/destroy_service_test.rb"
    end
  end
end
