# frozen_string_literal: true

# Repository for Article model data access.
#
# Provides a clean abstraction layer between services and ActiveRecord.
# The model class is automatically inferred from the repository name:
#   ArticleRepository -> Article
#
# Inherited methods from BaseRepository:
# - find(id), find_by(attributes), where(conditions)
# - create(attributes), create!(attributes)
# - update(record, attributes), update!(record, attributes)
# - destroy(record), destroy!(record)
# - search(predicates, page:, per_page:, includes:, order:)
# - all, count, exists?
#
# @example Basic usage
#   repo = ArticleRepository.new
#   repo.find(1)
#   repo.search({ status_eq: 'active' }, page: 1, per_page: 20)
#
# @example In services (via RepositoryAware)
#   class Article::IndexService < Article::BaseService
#     search_with do
#       { items: article_repository.active.recent.to_a }
#     end
#   end
#
class ArticleRepository < BetterService::Repository::BaseRepository
  # Model is inferred automatically: ArticleRepository -> Article
  # Override with explicit model if needed:
  # def initialize(model_class = Article)
  #   super
  # end

  # Add custom repository methods below:

  # @example Scope methods
  # def active
  #   where(active: true)
  # end
  #
  # def inactive
  #   where(active: false)
  # end

  # @example Ownership methods
  # def for_user(user)
  #   where(user_id: user.id)
  # end
  #
  # def for_organization(org)
  #   where(organization_id: org.id)
  # end

  # @example Ordering methods
  # def recent(limit = 10)
  #   model.order(created_at: :desc).limit(limit)
  # end
  #
  # def by_name
  #   model.order(:name)
  # end

  # @example Complex queries
  # def with_associations
  #   model.includes(:user, :category)
  # end
  #
  # def published_today
  #   where(published: true)
  #     .where("published_at >= ?", Time.current.beginning_of_day)
  # end
end
