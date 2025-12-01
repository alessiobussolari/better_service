# frozen_string_literal: true

require "rails_helper"
require "generators/serviceable/index_generator"

RSpec.describe Serviceable::Generators::IndexGenerator, type: :generator do
  tests Serviceable::Generators::IndexGenerator

  describe "generating index service" do
    it "generates index service file" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/index_service.rb" do |content|
        expect(content).to match(/class Booking::IndexService < BetterService::Services::Base/)
        expect(content).to match(/frozen_string_literal: true/)
      end
    end

    it "generates service with performed_action :listed" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/index_service.rb" do |content|
        expect(content).to match(/performed_action :listed/)
      end
    end

    it "generates service with schema" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/index_service.rb" do |content|
        expect(content).to match(/schema do/)
        expect(content).to match(/optional\(:page\)/)
        expect(content).to match(/optional\(:per_page\)/)
        expect(content).to match(/optional\(:search\)/)
      end
    end

    it "generates service with search_with block" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/index_service.rb" do |content|
        expect(content).to match(/search_with do/)
        expect(content).to match(/bookings = user\.bookings/)
      end
    end

    it "generates service with process_with block including metadata" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/index_service.rb" do |content|
        expect(content).to match(/process_with do \|data\|/)
        expect(content).to match(/metadata:/)
        expect(content).to match(/stats:/)
        expect(content).to match(/pagination:/)
      end
    end

    it "generates service with respond_with block" do
      run_generator [ "booking" ]

      assert_file "app/services/booking/index_service.rb" do |content|
        expect(content).to match(/respond_with do \|data\|/)
        expect(content).to match(/success_for/)
      end
    end

    it "generates test file" do
      run_generator [ "booking" ]

      assert_file "test/services/booking/index_service_test.rb" do |content|
        expect(content).to match(/class Booking::IndexServiceTest < ActiveSupport::TestCase/)
        expect(content).to match(/def setup/)
      end
    end
  end

  describe "namespaced models" do
    it "handles namespaced models" do
      run_generator [ "admin/booking" ]

      assert_file "app/services/admin/booking/index_service.rb" do |content|
        expect(content).to match(/class Admin::Booking::IndexService < BetterService::Services::Base/)
      end
    end
  end
end
