# frozen_string_literal: true

require "test_helper"

class Article::BaseServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:one) # Adjust fixture name as needed
  end

  # Test that the base service cannot be called directly
  # (it requires subclass implementation)
  test "base service requires schema definition" do
    assert_raises(BetterService::Errors::Configuration::SchemaRequiredError) do
      Article::BaseService.new(@user, params: {})
    end
  end

  test "messages_namespace is configured" do
    assert_equal :article, Article::BaseService._messages_namespace
  end

  test "cache_contexts is configured" do
    assert_includes Article::BaseService._cache_contexts, :articles
  end
end
