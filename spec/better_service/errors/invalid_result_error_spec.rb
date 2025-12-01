# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterService::Errors::Runtime::InvalidResultError do
  describe "#initialize" do
    it "creates error with default message" do
      error = described_class.new

      expect(error.message).to eq("Service must return BetterService::Result")
      expect(error.code).to eq(:invalid_result)
      expect(error.context).to eq({})
    end

    it "creates error with custom message" do
      error = described_class.new("Custom error message")

      expect(error.message).to eq("Custom error message")
      expect(error.code).to eq(:invalid_result)
    end

    it "creates error with context" do
      error = described_class.new(
        "Service MyService must return BetterService::Result",
        context: { service: "MyService", result_class: "Hash" }
      )

      expect(error.context[:service]).to eq("MyService")
      expect(error.context[:result_class]).to eq("Hash")
    end
  end

  describe "inheritance" do
    it "inherits from RuntimeError" do
      expect(described_class.superclass).to eq(BetterService::Errors::Runtime::RuntimeError)
    end

    it "inherits from BetterServiceError" do
      expect(described_class.ancestors).to include(BetterService::BetterServiceError)
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      error = described_class.new(
        "Service failed",
        context: { service: "TestService" }
      )

      hash = error.to_h

      expect(hash[:error_class]).to eq("BetterService::Errors::Runtime::InvalidResultError")
      expect(hash[:message]).to eq("Service failed")
      expect(hash[:code]).to eq(:invalid_result)
      expect(hash[:context][:service]).to eq("TestService")
    end
  end
end
