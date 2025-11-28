# frozen_string_literal: true

# BaseService for Article resource operations.
#
# Provides centralized configuration for all Article services:
# - Repository access via RepositoryAware concern
# - I18n messages namespace
# - Cache invalidation contexts
# - Presenter configuration
#
# All Article services should inherit from this class:
#   class Article::IndexService < Article::BaseService
#   class Article::CreateService < Article::BaseService
#
# @example Usage
#   class Article::IndexService < Article::BaseService
#     schema do
#       optional(:page).filled(:integer, gteq?: 1)
#     end
#
#     search_with do
#       { items: article_repository.all.to_a }
#     end
#   end
#
class Article::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  # I18n messages namespace - messages are loaded from:
  # config/locales/article_services.en.yml
  messages_namespace :article

  # Cache contexts for automatic invalidation
  # Create/Update/Destroy services will invalidate these contexts
  cache_contexts [:articles]

  # Presenter for transforming data in responses
  # Generate with: rails generate better_service:presenter Article
  # presenter ArticlePresenter
  # presenter_options do
  #   { current_user: user }
  # end

  private

  # Override to provide default error message for this resource
  def default_error_message
    message("common.error")
  end

  # Override to provide default success message for this resource
  def default_success_message
    message("common.success")
  end

  # Add shared helper methods for all Article services here:
  #
  # def find_article(id)
  #   article_repository.find(id)
  # end
  #
  # def article_authorized?(record)
  #   record.user_id == user.id
  # end
end
