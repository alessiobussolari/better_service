# frozen_string_literal: true

# Shared examples for successful service responses
RSpec.shared_examples "a successful service" do
  it "returns success" do
    expect(result).to be_success
  end
end

# Shared examples for failed service responses
RSpec.shared_examples "a failed service" do
  it "returns failure" do
    expect(result).to be_failure
  end
end

# Shared examples for services that require authentication
RSpec.shared_examples "requires user" do
  context "when user is nil" do
    let(:user) { nil }

    it "raises NilUserError" do
      expect { service }.to raise_error(BetterService::Errors::Configuration::NilUserError)
    end
  end
end

# Shared examples for services with validation
RSpec.shared_examples "validates params" do |invalid_params, expected_error_keys|
  context "with invalid params" do
    let(:params) { invalid_params }

    it "raises ValidationError" do
      expect { service }.to raise_error(BetterService::Errors::Runtime::ValidationError) do |error|
        expected_error_keys.each do |key|
          expect(error.context[:validation_errors]).to have_key(key)
        end
      end
    end
  end
end

# Shared examples for Result objects
RSpec.shared_examples "a result object" do
  it "responds to resource" do
    expect(result).to respond_to(:resource)
  end

  it "responds to meta" do
    expect(result).to respond_to(:meta)
  end

  it "responds to success?" do
    expect(result).to respond_to(:success?)
  end

  it "responds to failure?" do
    expect(result).to respond_to(:failure?)
  end

  it "supports destructuring" do
    resource, meta = result
    expect(meta).to be_a(Hash)
  end
end
