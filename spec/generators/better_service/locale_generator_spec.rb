# frozen_string_literal: true

require "rails_helper"
require "generators/better_service/locale_generator"

RSpec.describe BetterService::Generators::LocaleGenerator, type: :generator do
  tests BetterService::Generators::LocaleGenerator

  describe "generating locale file" do
    it "generates locale file with default actions" do
      run_generator [ "booking" ]

      assert_file "config/locales/bookings_services.en.yml" do |content|
        expect(content).to match(/en:/)
        expect(content).to match(/bookings:/)
        expect(content).to match(/services:/)
        expect(content).to match(/create:/)
        expect(content).to match(/update:/)
        expect(content).to match(/destroy:/)
        expect(content).to match(/index:/)
        expect(content).to match(/show:/)
      end
    end

    it "generates locale file with custom actions" do
      run_generator [ "booking", "--actions=publish", "archive" ]

      assert_file "config/locales/bookings_services.en.yml" do |content|
        expect(content).to match(/publish:/)
        expect(content).to match(/archive:/)
      end
    end

    it "uses pluralized file name" do
      run_generator [ "user" ]

      assert_file "config/locales/users_services.en.yml"
    end

    it "generates valid YAML structure" do
      run_generator [ "booking" ]

      assert_file "config/locales/bookings_services.en.yml" do |content|
        expect { YAML.safe_load(content) }.not_to raise_error
      end
    end

    it "includes success and failure messages for each action" do
      run_generator [ "booking" ]

      assert_file "config/locales/bookings_services.en.yml" do |content|
        expect(content).to match(/success:/)
        expect(content).to match(/failure:/)
      end
    end
  end
end
