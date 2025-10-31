# frozen_string_literal: true

require "test_helper"

class Product::IndexServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:one) # Assumes you have fixtures
  end

  test "service executes successfully" do
    service = Product::IndexService.new(@user)
    result = service.call

    assert result[:success]
    assert result.key?(:metadata)
  end

  test "service validates params" do
    # Add validation tests based on your schema
  end
end
