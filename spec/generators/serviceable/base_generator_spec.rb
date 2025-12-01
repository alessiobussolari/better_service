# frozen_string_literal: true

require "rails_helper"
require "generators/serviceable/base_generator"

RSpec.describe Serviceable::Generators::BaseGenerator, type: :generator do
  tests Serviceable::Generators::BaseGenerator

  describe "generating base service" do
    it "generates base service file" do
      run_generator [ "article" ]

      assert_file "app/services/article/base_service.rb" do |content|
        expect(content).to match(/frozen_string_literal: true/)
        expect(content).to match(/class Article::BaseService < BetterService::Services::Base/)
      end
    end

    it "generates base service with RepositoryAware concern" do
      run_generator [ "article" ]

      assert_file "app/services/article/base_service.rb" do |content|
        expect(content).to match(/include BetterService::Concerns::Serviceable::RepositoryAware/)
      end
    end

    it "generates base service with messages_namespace" do
      run_generator [ "article" ]

      assert_file "app/services/article/base_service.rb" do |content|
        expect(content).to match(/messages_namespace :article/)
      end
    end

    it "generates base service with cache_contexts" do
      run_generator [ "article" ]

      assert_file "app/services/article/base_service.rb" do |content|
        expect(content).to match(/cache_contexts \[:articles\]/)
      end
    end

    it "generates base service with repository declaration" do
      run_generator [ "article" ]

      assert_file "app/services/article/base_service.rb" do |content|
        expect(content).to match(/repository :article/)
      end
    end
  end

  describe "generating repository" do
    it "generates repository file" do
      run_generator [ "article" ]

      assert_file "app/repositories/article_repository.rb" do |content|
        expect(content).to match(/frozen_string_literal: true/)
        expect(content).to match(/class ArticleRepository < BetterService::Repository::BaseRepository/)
      end
    end
  end

  describe "generating locale" do
    it "generates locale file" do
      run_generator [ "article" ]

      assert_file "config/locales/article_services.en.yml" do |content|
        expect(content).to match(/article:/)
        expect(content).to match(/services:/)
        expect(content).to match(/index:/)
        expect(content).to match(/show:/)
        expect(content).to match(/create:/)
        expect(content).to match(/update:/)
        expect(content).to match(/destroy:/)
        expect(content).to match(/common:/)
      end
    end
  end

  describe "generating tests" do
    it "generates base service test file" do
      run_generator [ "article" ]

      assert_file "test/services/article/base_service_test.rb" do |content|
        expect(content).to match(/class Article::BaseServiceTest < ActiveSupport::TestCase/)
        expect(content).to match(/messages_namespace is configured/)
        expect(content).to match(/cache_contexts is configured/)
      end
    end

    it "generates repository test file" do
      run_generator [ "article" ]

      assert_file "test/repositories/article_repository_test.rb" do |content|
        expect(content).to match(/class ArticleRepositoryTest < ActiveSupport::TestCase/)
        expect(content).to match(/repository infers model class correctly/)
      end
    end
  end

  describe "namespaced models" do
    it "handles namespaced models" do
      run_generator [ "admin/article" ]

      assert_file "app/services/admin/article/base_service.rb" do |content|
        expect(content).to match(/class Admin::Article::BaseService < BetterService::Services::Base/)
        expect(content).to match(/messages_namespace :article/)
        expect(content).to match(/repository :admin_article/)
      end

      assert_file "app/repositories/admin/article_repository.rb" do |content|
        expect(content).to match(/class Admin::ArticleRepository < BetterService::Repository::BaseRepository/)
      end
    end
  end

  describe "skip options" do
    it "skip_repository option works" do
      run_generator [ "article", "--skip_repository" ]

      assert_file "app/services/article/base_service.rb"
      assert_no_file "app/repositories/article_repository.rb"
      assert_no_file "test/repositories/article_repository_test.rb"
    end

    it "skip_locale option works" do
      run_generator [ "article", "--skip_locale" ]

      assert_file "app/services/article/base_service.rb"
      assert_no_file "config/locales/article_services.en.yml"
    end

    it "skip_test option works" do
      run_generator [ "article", "--skip_test" ]

      assert_file "app/services/article/base_service.rb"
      assert_file "app/repositories/article_repository.rb"
      assert_no_file "test/services/article/base_service_test.rb"
      assert_no_file "test/repositories/article_repository_test.rb"
    end
  end
end
