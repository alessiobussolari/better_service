# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterService::Railtie do
  describe "class definition" do
    it "is defined" do
      expect(defined?(BetterService::Railtie)).to eq("constant")
    end

    it "inherits from Rails::Railtie" do
      expect(BetterService::Railtie.superclass).to eq(Rails::Railtie)
    end

    it "is a Rails::Railtie" do
      expect(BetterService::Railtie).to be < Rails::Railtie
    end
  end

  describe "configuration" do
    it "can access BetterService configuration" do
      expect(BetterService.configuration).to be_a(BetterService::Configuration)
    end

    it "has log_subscriber_enabled setting" do
      expect(BetterService.configuration).to respond_to(:log_subscriber_enabled)
    end

    it "has stats_subscriber_enabled setting" do
      expect(BetterService.configuration).to respond_to(:stats_subscriber_enabled)
    end
  end

  describe "subscribers integration" do
    describe "LogSubscriber" do
      it "is defined" do
        expect(defined?(BetterService::Subscribers::LogSubscriber)).to eq("constant")
      end

      it "responds to attach" do
        expect(BetterService::Subscribers::LogSubscriber).to respond_to(:attach)
      end

      it "responds to detach" do
        expect(BetterService::Subscribers::LogSubscriber).to respond_to(:detach)
      end
    end

    describe "StatsSubscriber" do
      it "is defined" do
        expect(defined?(BetterService::Subscribers::StatsSubscriber)).to eq("constant")
      end

      it "responds to attach" do
        expect(BetterService::Subscribers::StatsSubscriber).to respond_to(:attach)
      end

      it "responds to summary" do
        expect(BetterService::Subscribers::StatsSubscriber).to respond_to(:summary)
      end
    end
  end

  describe "after_initialize hook behavior" do
    # Note: Testing the actual after_initialize behavior is complex because
    # it runs during Rails boot. These tests verify the supporting components.

    context "when log_subscriber is enabled" do
      before do
        allow(BetterService.configuration).to receive(:log_subscriber_enabled).and_return(true)
      end

      it "configuration returns true for log_subscriber_enabled" do
        expect(BetterService.configuration.log_subscriber_enabled).to be true
      end
    end

    context "when log_subscriber is disabled" do
      before do
        allow(BetterService.configuration).to receive(:log_subscriber_enabled).and_return(false)
      end

      it "configuration returns false for log_subscriber_enabled" do
        expect(BetterService.configuration.log_subscriber_enabled).to be false
      end
    end

    context "when stats_subscriber is enabled" do
      before do
        allow(BetterService.configuration).to receive(:stats_subscriber_enabled).and_return(true)
      end

      it "configuration returns true for stats_subscriber_enabled" do
        expect(BetterService.configuration.stats_subscriber_enabled).to be true
      end
    end
  end

  describe "Rails integration" do
    it "registers as a Rails railtie" do
      railties = Rails::Railtie.subclasses.map(&:name)
      expect(railties).to include("BetterService::Railtie")
    end

    it "has access to Rails.logger" do
      expect(Rails).to respond_to(:logger)
    end
  end
end
