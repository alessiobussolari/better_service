# frozen_string_literal: true

require "test_helper"
require "generators/serviceable/base_generator"

class BaseGeneratorTest < Rails::Generators::TestCase
  tests Serviceable::Generators::BaseGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  test "generates base service file" do
    run_generator ["article"]

    assert_file "app/services/article/base_service.rb" do |content|
      assert_match(/frozen_string_literal: true/, content)
      assert_match(/class Article::BaseService < BetterService::Services::Base/, content)
    end
  end

  test "generates base service with RepositoryAware concern" do
    run_generator ["article"]

    assert_file "app/services/article/base_service.rb" do |content|
      assert_match(/include BetterService::Concerns::Serviceable::RepositoryAware/, content)
    end
  end

  test "generates base service with messages_namespace" do
    run_generator ["article"]

    assert_file "app/services/article/base_service.rb" do |content|
      assert_match(/messages_namespace :article/, content)
    end
  end

  test "generates base service with cache_contexts" do
    run_generator ["article"]

    assert_file "app/services/article/base_service.rb" do |content|
      assert_match(/cache_contexts \[:articles\]/, content)
    end
  end

  test "generates base service with repository declaration" do
    run_generator ["article"]

    assert_file "app/services/article/base_service.rb" do |content|
      assert_match(/repository :article/, content)
    end
  end

  test "generates repository file" do
    run_generator ["article"]

    assert_file "app/repositories/article_repository.rb" do |content|
      assert_match(/frozen_string_literal: true/, content)
      assert_match(/class ArticleRepository < BetterService::Repository::BaseRepository/, content)
    end
  end

  test "generates locale file" do
    run_generator ["article"]

    assert_file "config/locales/article_services.en.yml" do |content|
      assert_match(/article:/, content)
      assert_match(/services:/, content)
      assert_match(/index:/, content)
      assert_match(/show:/, content)
      assert_match(/create:/, content)
      assert_match(/update:/, content)
      assert_match(/destroy:/, content)
      assert_match(/common:/, content)
    end
  end

  test "generates base service test file" do
    run_generator ["article"]

    assert_file "test/services/article/base_service_test.rb" do |content|
      assert_match(/class Article::BaseServiceTest < ActiveSupport::TestCase/, content)
      assert_match(/messages_namespace is configured/, content)
      assert_match(/cache_contexts is configured/, content)
    end
  end

  test "generates repository test file" do
    run_generator ["article"]

    assert_file "test/repositories/article_repository_test.rb" do |content|
      assert_match(/class ArticleRepositoryTest < ActiveSupport::TestCase/, content)
      assert_match(/repository infers model class correctly/, content)
    end
  end

  test "handles namespaced models" do
    run_generator ["admin/article"]

    assert_file "app/services/admin/article/base_service.rb" do |content|
      assert_match(/class Admin::Article::BaseService < BetterService::Services::Base/, content)
      assert_match(/messages_namespace :article/, content)
      # For namespaced models, repository uses full singular name (admin_article)
      assert_match(/repository :admin_article/, content)
    end

    assert_file "app/repositories/admin/article_repository.rb" do |content|
      assert_match(/class Admin::ArticleRepository < BetterService::Repository::BaseRepository/, content)
    end
  end

  test "skip_repository option works" do
    run_generator ["article", "--skip_repository"]

    assert_file "app/services/article/base_service.rb"
    assert_no_file "app/repositories/article_repository.rb"
    assert_no_file "test/repositories/article_repository_test.rb"
  end

  test "skip_locale option works" do
    run_generator ["article", "--skip_locale"]

    assert_file "app/services/article/base_service.rb"
    assert_no_file "config/locales/article_services.en.yml"
  end

  test "skip_test option works" do
    run_generator ["article", "--skip_test"]

    assert_file "app/services/article/base_service.rb"
    assert_file "app/repositories/article_repository.rb"
    assert_no_file "test/services/article/base_service_test.rb"
    assert_no_file "test/repositories/article_repository_test.rb"
  end
end
