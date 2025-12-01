# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterService::Configuration do
  subject(:config) { described_class.new }

  describe "default values" do
    describe "#instrumentation_enabled" do
      it "defaults to true" do
        expect(config.instrumentation_enabled).to be true
      end
    end

    describe "#instrumentation_include_args" do
      it "defaults to true" do
        expect(config.instrumentation_include_args).to be true
      end
    end

    describe "#instrumentation_include_result" do
      it "defaults to false" do
        expect(config.instrumentation_include_result).to be false
      end
    end

    describe "#instrumentation_excluded_services" do
      it "defaults to empty array" do
        expect(config.instrumentation_excluded_services).to eq([])
      end
    end

    describe "#log_subscriber_enabled" do
      it "defaults to false" do
        expect(config.log_subscriber_enabled).to be false
      end
    end

    describe "#log_subscriber_level" do
      it "defaults to :info" do
        expect(config.log_subscriber_level).to eq(:info)
      end
    end

    describe "#stats_subscriber_enabled" do
      it "defaults to false" do
        expect(config.stats_subscriber_enabled).to be false
      end
    end

    describe "#cache_invalidation_map" do
      it "defaults to empty hash" do
        expect(config.cache_invalidation_map).to eq({})
      end
    end
  end

  describe "setters" do
    describe "#instrumentation_enabled=" do
      it "allows setting to false" do
        config.instrumentation_enabled = false
        expect(config.instrumentation_enabled).to be false
      end
    end

    describe "#instrumentation_include_args=" do
      it "allows setting to false" do
        config.instrumentation_include_args = false
        expect(config.instrumentation_include_args).to be false
      end
    end

    describe "#instrumentation_include_result=" do
      it "allows setting to true" do
        config.instrumentation_include_result = true
        expect(config.instrumentation_include_result).to be true
      end
    end

    describe "#instrumentation_excluded_services=" do
      it "allows setting services list" do
        services = [ "HealthCheckService", "PingService" ]
        config.instrumentation_excluded_services = services
        expect(config.instrumentation_excluded_services).to eq(services)
      end
    end

    describe "#log_subscriber_enabled=" do
      it "allows setting to true" do
        config.log_subscriber_enabled = true
        expect(config.log_subscriber_enabled).to be true
      end
    end

    describe "#log_subscriber_level=" do
      it "allows setting to :debug" do
        config.log_subscriber_level = :debug
        expect(config.log_subscriber_level).to eq(:debug)
      end
    end

    describe "#stats_subscriber_enabled=" do
      it "allows setting to true" do
        config.stats_subscriber_enabled = true
        expect(config.stats_subscriber_enabled).to be true
      end
    end
  end

  describe "BetterService module methods" do
    describe ".configuration" do
      it "returns Configuration instance" do
        expect(BetterService.configuration).to be_an_instance_of(described_class)
      end

      it "returns same instance on multiple calls" do
        config1 = BetterService.configuration
        config2 = BetterService.configuration
        expect(config1).to be(config2)
      end
    end

    describe ".configure" do
      it "yields configuration object" do
        yielded_config = nil

        BetterService.configure do |c|
          yielded_config = c
        end

        expect(yielded_config).to be(BetterService.configuration)
      end

      it "allows setting options" do
        BetterService.configure do |c|
          c.instrumentation_enabled = false
          c.log_subscriber_enabled = true
          c.log_subscriber_level = :warn
        end

        expect(BetterService.configuration.instrumentation_enabled).to be false
        expect(BetterService.configuration.log_subscriber_enabled).to be true
        expect(BetterService.configuration.log_subscriber_level).to eq(:warn)
      end
    end

    describe ".reset_configuration!" do
      it "creates new instance" do
        original_config = BetterService.configuration
        original_config.instrumentation_enabled = false

        BetterService.reset_configuration!

        new_config = BetterService.configuration
        expect(new_config).not_to be(original_config)
        expect(new_config.instrumentation_enabled).to be true
      end
    end
  end

  describe "#cache_invalidation_map=" do
    it "stores the map" do
      map = { "products" => %w[products inventory], "orders" => %w[orders products] }
      config.cache_invalidation_map = map
      expect(config.cache_invalidation_map).to eq(map)
    end

    it "configures CacheService" do
      original_map = BetterService::CacheService.instance_variable_get(:@invalidation_map) || {}

      begin
        BetterService::CacheService.configure_invalidation_map({})

        map = { "test_context" => %w[test_context related_context] }
        config.cache_invalidation_map = map

        expect(BetterService::CacheService.instance_variable_get(:@invalidation_map)).to eq(map)
      ensure
        BetterService::CacheService.configure_invalidation_map(original_map)
      end
    end

    it "handles nil gracefully" do
      config.cache_invalidation_map = nil
      expect(config.cache_invalidation_map).to be_nil
    end
  end

  describe "full configuration flow" do
    it "works correctly" do
      BetterService.configure do |c|
        c.instrumentation_enabled = true
        c.instrumentation_include_args = false
        c.instrumentation_include_result = true
        c.instrumentation_excluded_services = [ "HealthCheckService" ]
        c.log_subscriber_enabled = true
        c.log_subscriber_level = :debug
        c.stats_subscriber_enabled = true
      end

      result = BetterService.configuration

      expect(result.instrumentation_enabled).to be true
      expect(result.instrumentation_include_args).to be false
      expect(result.instrumentation_include_result).to be true
      expect(result.instrumentation_excluded_services).to eq([ "HealthCheckService" ])
      expect(result.log_subscriber_enabled).to be true
      expect(result.log_subscriber_level).to eq(:debug)
      expect(result.stats_subscriber_enabled).to be true
    end
  end
end
