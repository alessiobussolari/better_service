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

  # Repository tests
  # Note: These tests verify the repository declaration works
  # Actual repository functionality is tested in repository_test.rb

  test "repository is accessible via method" do
    # Create a concrete subclass to test repository access
    test_service_class = Class.new(Article::BaseService) do
      schema { optional(:id).filled }

      def test_repository_access
        article_repository
      end
    end

    service = test_service_class.new(@user, params: {})
    repo = service.send(:test_repository_access)

    assert_instance_of ArticleRepository, repo
  end

  test "repository is memoized" do
    test_service_class = Class.new(Article::BaseService) do
      schema { optional(:id).filled }

      def test_repository_memoization
        [article_repository, article_repository]
      end
    end

    service = test_service_class.new(@user, params: {})
    repos = service.send(:test_repository_memoization)

    assert_same repos[0], repos[1], "Repository should be memoized"
  end
end
