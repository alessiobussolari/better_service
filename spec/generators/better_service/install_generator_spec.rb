# frozen_string_literal: true

require "rails_helper"
require "generators/better_service/install_generator"

RSpec.describe BetterService::Generators::InstallGenerator, type: :generator do
  tests BetterService::Generators::InstallGenerator

  describe "generating initializer" do
    it "generates initializer file" do
      run_generator

      assert_file "config/initializers/better_service.rb" do |content|
        expect(content).to match(/BetterService\.configure do \|config\|/)
        expect(content).to match(/config\.instrumentation_enabled/)
      end
    end

    it "initializer includes all configuration options" do
      run_generator

      assert_file "config/initializers/better_service.rb" do |content|
        expect(content).to match(/instrumentation/)
        expect(content).to match(/log_subscriber/)
        expect(content).to match(/stats_subscriber/)
      end
    end
  end

  describe "generating locale" do
    it "copies locale file" do
      run_generator

      assert_file "config/locales/better_service.en.yml" do |content|
        expect(content).to match(/en:/)
        expect(content).to match(/better_service:/)
        expect(content).to match(/services:/)
        expect(content).to match(/default:/)
        expect(content).to match(/created:/)
        expect(content).to match(/updated:/)
        expect(content).to match(/deleted:/)
        expect(content).to match(/listed:/)
        expect(content).to match(/shown:/)
      end
    end

    it "locale file is valid YAML" do
      run_generator

      assert_file "config/locales/better_service.en.yml" do |content|
        expect { YAML.safe_load(content) }.not_to raise_error
      end
    end
  end
end
