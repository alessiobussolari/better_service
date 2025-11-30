# frozen_string_literal: true

require "rails_helper"
require "generators/serviceable/update_generator"

RSpec.describe Serviceable::Generators::UpdateGenerator, type: :generator do
  tests Serviceable::Generators::UpdateGenerator

  describe "generating update service" do
    it "generates update service file" do
      run_generator ["booking"]

      assert_file "app/services/booking/update_service.rb" do |content|
        expect(content).to match(/class Booking::UpdateService < BetterService::Services::Base/)
      end
    end

    it "generates service with performed_action :updated" do
      run_generator ["booking"]

      assert_file "app/services/booking/update_service.rb" do |content|
        expect(content).to match(/performed_action :updated/)
      end
    end

    it "generates service with transaction enabled" do
      run_generator ["booking"]

      assert_file "app/services/booking/update_service.rb" do |content|
        expect(content).to match(/with_transaction true/)
      end
    end

    it "generates service with process_with block" do
      run_generator ["booking"]

      assert_file "app/services/booking/update_service.rb" do |content|
        expect(content).to match(/process_with do/)
        expect(content).to match(/record\.update\(params\.except\(:id\)\)/)
      end
    end

    it "generates test file" do
      run_generator ["booking"]

      assert_file "test/services/booking/update_service_test.rb"
    end
  end
end
