# frozen_string_literal: true

# Helper methods for service specs
module ServiceHelpers
  # Creates a simple test service class
  def create_test_service(parent: BetterService::Services::Base, &block)
    Class.new(parent) do
      schema { }
      class_eval(&block) if block_given?
    end
  end

  # Creates a test service with custom schema
  def create_service_with_schema(schema_block, &service_block)
    Class.new(BetterService::Services::Base) do
      schema(&schema_block)
      class_eval(&service_block) if service_block
    end
  end

  # Creates a dummy user object for testing
  def build_dummy_user(id: 1, name: "Test User", admin: false)
    Struct.new(:id, :name, :admin?, keyword_init: true).new(
      id: id,
      name: name,
      admin?: admin
    )
  end
end

RSpec.configure do |config|
  config.include ServiceHelpers
end
