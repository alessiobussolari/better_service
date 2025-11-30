# frozen_string_literal: true

RSpec.shared_examples "a successful service" do
  it "returns success" do
    expect(result.success?).to be true
  end

  it "includes metadata" do
    expect(result.meta).to be_present
  end
end

RSpec.shared_examples "a service with validation error" do
  it "returns a failure result with validation error" do
    result = service.call
    expect(result.success?).to be false
    expect(result.meta[:error_code]).to eq(:validation_failed)
  end
end

RSpec.shared_examples "a service with authorization error" do
  it "returns a failure result with authorization error" do
    result = service.call
    expect(result.success?).to be false
    expect(result.meta[:error_code]).to eq(:unauthorized)
  end
end

RSpec.shared_examples "a service with resource not found error" do
  it "returns a failure result with resource not found error" do
    result = service.call
    expect(result.success?).to be false
    expect(result.meta[:error_code]).to eq(:resource_not_found)
  end
end

RSpec.shared_examples "a service that invalidates cache" do |contexts|
  it "invalidates cache for specified contexts" do
    contexts.each do |context|
      expect_any_instance_of(described_class).to receive(:invalidate_cache_for).with(context)
    end
    service.call
  end
end

RSpec.shared_examples "a transactional service" do
  it "wraps in a transaction" do
    expect(ActiveRecord::Base).to receive(:transaction).and_call_original
    service.call
  end
end
