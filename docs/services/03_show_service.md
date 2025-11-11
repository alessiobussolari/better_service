# ShowService

## Overview

ShowService is designed for retrieving a single resource by ID. It's optimized for detail views with authorization checks, eager loading, and automatic caching support.

**Characteristics:**
- **Action**: `:show`
- **Transaction**: Disabled (read-only operation)
- **Return Key**: `resource` (object/hash)
- **Default Schema**: Required `id` parameter
- **Common Use Cases**: Detail pages, resource retrieval, view endpoints

## Generation

### Basic Generation

```bash
rails g serviceable:show Product
```

This generates:

```ruby
# app/services/product/show_service.rb
module Product
  class ShowService < BetterService::ShowService
    model_class Product

    schema do
      required(:id).filled(:integer)
    end

    search_with do
      resource = model_class.find(params[:id])
      { resource: resource }
    end
  end
end
```

### Generation with Options

```bash
# With cache enabled
rails g serviceable:show Product --cache

# With presenter
rails g serviceable:show Product --presenter=ProductPresenter

# With authorization
rails g serviceable:show Product --authorize

# With specific namespace
rails g serviceable:show Admin::Product
```

## Schema

### Default Schema

ShowService requires an ID parameter:

```ruby
schema do
  required(:id).filled(:integer)
end
```

### Custom Identifiers

Use different types of identifiers:

```ruby
# UUID identifier
schema do
  required(:id).filled(:string, format?: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
end

# Slug identifier
schema do
  required(:slug).filled(:string)
end

# Composite key
schema do
  required(:user_id).filled(:integer)
  required(:post_id).filled(:integer)
end
```

### Additional Parameters

Include query options:

```ruby
schema do
  required(:id).filled(:integer)
  optional(:include_deleted).maybe(:bool)
  optional(:locale).maybe(:string, included_in?: %w[en it fr es])
end
```

## Available Methods

### search_with

Loads the resource from database.

**Returns**: Hash with `:resource` key containing the object.

```ruby
# Basic find
search_with do
  { resource: model_class.find(params[:id]) }
end

# With eager loading
search_with do
  resource = model_class.includes(:category, :reviews, :images).find(params[:id])
  { resource: resource }
end

# Find by slug
search_with do
  resource = model_class.find_by!(slug: params[:slug])
  { resource: resource }
end

# With soft delete support
search_with do
  scope = params[:include_deleted] ? model_class.with_deleted : model_class
  { resource: scope.find(params[:id]) }
end

# Composite key
search_with do
  resource = Comment.find_by!(
    user_id: params[:user_id],
    post_id: params[:post_id]
  )
  { resource: resource }
end
```

### process_with

Enriches or transforms the resource data.

**Input**: Hash from search (`:resource` key)
**Returns**: Hash with `:resource` key and optional metadata

```ruby
# Add metadata
process_with do |data|
  resource = data[:resource]

  {
    resource: resource,
    metadata: {
      views: resource.view_count,
      last_updated: resource.updated_at
    }
  }
end

# Track view
process_with do |data|
  resource = data[:resource]
  resource.increment!(:view_count)

  { resource: resource }
end

# Add related data
process_with do |data|
  resource = data[:resource]

  {
    resource: resource,
    related_products: Product.where(category: resource.category).limit(5)
  }
end
```

### respond_with

Customizes the final response format.

**Input**: Hash from process/transform
**Returns**: Hash with `:success`, `:message`, and data

```ruby
# Custom message
respond_with do |data|
  success_result("#{data[:resource].name} loaded successfully", data)
end

# Add timestamp
respond_with do |data|
  success_result("Resource loaded", data).merge(
    loaded_at: Time.current
  )
end
```

## Configurations

### Authorization Configuration

Ensure user can access the resource:

```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    resource = model_class.find(params[:id])

    # Only admins or owners can view
    user.admin? || resource.user_id == user.id
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end
end
```

### Cache Configuration

Enable automatic caching:

```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product
  cache_contexts :product

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.includes(:category, :reviews).find(params[:id]) }
  end
end
```

### Presenter Configuration

Format the resource output:

```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product
  presenter ProductPresenter

  search_with do
    { resource: model_class.includes(:category, :reviews, :images).find(params[:id]) }
  end
end
```

Example presenter:

```ruby
class ProductPresenter
  def self.present(product)
    {
      id: product.id,
      name: product.name,
      description: product.description,
      price: product.price.to_f,
      category: {
        id: product.category.id,
        name: product.category.name
      },
      images: product.images.map { |img| img.url },
      rating: {
        average: product.reviews.average(:rating)&.round(1),
        count: product.reviews.count
      }
    }
  end
end
```

## Complete Examples

### Example 1: Basic Product Details

```ruby
module Product
  class ShowService < BetterService::ShowService
    model_class Product

    schema do
      required(:id).filled(:integer)
    end

    search_with do
      { resource: model_class.includes(:category, :reviews).find(params[:id]) }
    end
  end
end

# Usage
result = Product::ShowService.new(current_user, params: { id: 123 }).call
product = result[:resource]
```

### Example 2: With Authorization

```ruby
module Post
  class ShowService < BetterService::ShowService
    model_class Post
    presenter PostPresenter

    schema do
      required(:id).filled(:integer)
    end

    authorize_with do
      post = model_class.find(params[:id])

      # Public posts are visible to everyone
      # Private posts only to owner or admins
      post.public? || post.user_id == user.id || user.admin?
    end

    search_with do
      { resource: model_class.includes(:user, :comments, :tags).find(params[:id]) }
    end

    process_with do |data|
      post = data[:resource]

      # Track view (only for non-owners)
      post.increment!(:view_count) unless post.user_id == user.id

      { resource: post }
    end
  end
end

# Usage
begin
  result = Post::ShowService.new(current_user, params: { id: 456 }).call
  post = result[:resource]
rescue BetterService::Errors::Runtime::AuthorizationError
  render json: { error: "Not authorized" }, status: :forbidden
rescue ActiveRecord::RecordNotFound
  render json: { error: "Post not found" }, status: :not_found
end
```

### Example 3: Slug-based Lookup with Cache

```ruby
module Article
  class ShowBySlugService < BetterService::ShowService
    model_class Article
    cache_contexts :article
    presenter ArticlePresenter

    schema do
      required(:slug).filled(:string)
    end

    search_with do
      resource = model_class
        .includes(:author, :tags, comments: :user)
        .find_by!(slug: params[:slug])

      { resource: resource }
    end

    process_with do |data|
      article = data[:resource]

      {
        resource: article,
        metadata: {
          reading_time: calculate_reading_time(article.content),
          related_articles: find_related_articles(article)
        }
      }
    end

    private

    def calculate_reading_time(content)
      words = content.split.size
      (words / 200.0).ceil # 200 words per minute
    end

    def find_related_articles(article)
      Article
        .where.not(id: article.id)
        .joins(:tags)
        .where(tags: { id: article.tag_ids })
        .distinct
        .limit(5)
    end
  end
end

# Usage
result = Article::ShowBySlugService.new(current_user, params: {
  slug: "getting-started-with-rails"
}).call

article = result[:resource]
reading_time = result[:metadata][:reading_time]
related = result[:metadata][:related_articles]
```

### Example 4: Multi-Tenant with Composite Key

```ruby
module Workspace
  class DocumentShowService < BetterService::ShowService
    model_class Document

    schema do
      required(:workspace_id).filled(:integer)
      required(:document_id).filled(:integer)
    end

    authorize_with do
      # User must be member of workspace
      workspace = Workspace.find(params[:workspace_id])
      workspace.member?(user)
    end

    search_with do
      resource = model_class
        .includes(:versions, :attachments)
        .find_by!(
          workspace_id: params[:workspace_id],
          id: params[:document_id]
        )

      { resource: resource }
    end

    process_with do |data|
      document = data[:resource]

      {
        resource: document,
        metadata: {
          can_edit: can_edit?(document),
          can_delete: can_delete?(document),
          versions_count: document.versions.count
        }
      }
    end

    private

    def can_edit?(document)
      user.admin? || document.created_by_id == user.id
    end

    def can_delete?(document)
      user.admin?
    end
  end
end

# Usage
result = Workspace::DocumentShowService.new(current_user, params: {
  workspace_id: 10,
  document_id: 250
}).call
```

### Example 5: External API Integration

```ruby
module Github
  class RepositoryShowService < BetterService::ShowService
    self._allow_nil_user = true
    cache_contexts :github_repo

    schema do
      required(:owner).filled(:string)
      required(:repo).filled(:string)
    end

    search_with do
      repo_data = Octokit.repo("#{params[:owner]}/#{params[:repo]}")
      { resource: repo_data }
    rescue Octokit::NotFound
      raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
        "Repository not found"
      )
    rescue Octokit::Error => e
      raise BetterService::Errors::Runtime::ExecutionError.new(
        "GitHub API error: #{e.message}"
      )
    end

    process_with do |data|
      repo = data[:resource]

      {
        resource: {
          name: repo[:name],
          full_name: repo[:full_name],
          description: repo[:description],
          url: repo[:html_url],
          stars: repo[:stargazers_count],
          forks: repo[:forks_count],
          language: repo[:language],
          topics: repo[:topics],
          created_at: repo[:created_at],
          updated_at: repo[:updated_at]
        }
      }
    end
  end
end

# Usage
result = Github::RepositoryShowService.new(nil, params: {
  owner: "rails",
  repo: "rails"
}).call
```

## Best Practices

### 1. Always Use Eager Loading

```ruby
# ❌ Bad: Lazy loading causes N+1 queries
search_with do
  { resource: model_class.find(params[:id]) }
end

# ✅ Good: Eager load all associations
search_with do
  resource = model_class
    .includes(:category, :reviews, :images, comments: :user)
    .find(params[:id])

  { resource: resource }
end
```

### 2. Handle Not Found Gracefully

```ruby
# In controller
begin
  result = Product::ShowService.new(current_user, params: { id: params[:id] }).call
  render json: result[:resource]
rescue ActiveRecord::RecordNotFound
  render json: { error: "Product not found" }, status: :not_found
rescue BetterService::Errors::Runtime::AuthorizationError
  render json: { error: "Not authorized" }, status: :forbidden
end
```

### 3. Use Authorization for Privacy

```ruby
authorize_with do
  resource = model_class.find(params[:id])

  case resource.visibility
  when 'public'
    true
  when 'private'
    resource.user_id == user.id
  when 'team'
    resource.team.member?(user)
  else
    false
  end
end
```

### 4. Cache Expensive Queries

```ruby
class Product::ShowService < BetterService::ShowService
  cache_contexts :product

  search_with do
    # This expensive query will be cached
    resource = model_class
      .includes(:category, :reviews, :related_products)
      .find(params[:id])

    { resource: resource }
  end
end
```

### 5. Track Analytics in Process Phase

```ruby
process_with do |data|
  resource = data[:resource]

  # Track view asynchronously
  Analytics.track_view(
    user_id: user&.id,
    resource_type: resource.class.name,
    resource_id: resource.id
  )

  { resource: resource }
end
```

### 6. Return Related Data

```ruby
process_with do |data|
  product = data[:resource]

  {
    resource: product,
    related_products: Product
      .where(category_id: product.category_id)
      .where.not(id: product.id)
      .limit(5),
    recently_viewed: user.recently_viewed_products.limit(5)
  }
end
```

## Testing

### RSpec

```ruby
# spec/services/product/show_service_spec.rb
require 'rails_helper'

RSpec.describe Product::ShowService do
  let(:user) { create(:user) }
  let(:product) { create(:product, :with_reviews) }

  describe '#call' do
    it 'returns the product' do
      result = described_class.new(user, params: { id: product.id }).call

      expect(result[:success]).to be true
      expect(result[:resource]).to eq(product)
    end

    it 'includes associated data' do
      result = described_class.new(user, params: { id: product.id }).call

      # Associations should be loaded (no additional queries)
      expect { result[:resource].category.name }.not_to exceed_query_limit(0)
      expect { result[:resource].reviews.count }.not_to exceed_query_limit(0)
    end

    context 'when product does not exist' do
      it 'raises RecordNotFound error' do
        expect {
          described_class.new(user, params: { id: 99999 }).call
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe 'authorization' do
    let(:private_product) { create(:product, visibility: 'private', user: owner) }
    let(:owner) { create(:user) }
    let(:other_user) { create(:user) }

    it 'allows owner to view private product' do
      result = described_class.new(owner, params: { id: private_product.id }).call

      expect(result[:success]).to be true
    end

    it 'denies other users from viewing private product' do
      expect {
        described_class.new(other_user, params: { id: private_product.id }).call
      }.to raise_error(BetterService::Errors::Runtime::AuthorizationError)
    end
  end

  describe 'caching' do
    it 'caches the result' do
      service = described_class.new(user, params: { id: product.id })

      expect {
        service.call
      }.to change { Rails.cache.exist?("product:#{product.id}") }.to(true)
    end

    it 'uses cached result on second call' do
      described_class.new(user, params: { id: product.id }).call

      expect(Product).not_to receive(:find)
      described_class.new(user, params: { id: product.id }).call
    end
  end
end
```

### Minitest

```ruby
# test/services/product/show_service_test.rb
require 'test_helper'

class Product::ShowServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:regular_user)
    @product = products(:laptop)
  end

  test "returns the product" do
    result = Product::ShowService.new(@user, params: { id: @product.id }).call

    assert result[:success]
    assert_equal @product, result[:resource]
  end

  test "raises error when product not found" do
    assert_raises ActiveRecord::RecordNotFound do
      Product::ShowService.new(@user, params: { id: 99999 }).call
    end
  end

  test "denies access to private products" do
    private_product = products(:private_product)

    assert_raises BetterService::Errors::Runtime::AuthorizationError do
      Product::ShowService.new(@user, params: { id: private_product.id }).call
    end
  end

  test "caches the result" do
    cache_key = "product:#{@product.id}"

    Product::ShowService.new(@user, params: { id: @product.id }).call

    assert Rails.cache.exist?(cache_key)
  end
end
```

## Common Patterns

### Pattern 1: Conditional Eager Loading

```ruby
search_with do
  scope = model_class

  # Load different associations based on parameters
  scope = scope.includes(:reviews) if params[:include_reviews]
  scope = scope.includes(:comments) if params[:include_comments]

  { resource: scope.find(params[:id]) }
end
```

### Pattern 2: Versioning Support

```ruby
search_with do
  resource = if params[:version]
    model_class.find(params[:id]).versions.find(params[:version])
  else
    model_class.find(params[:id])
  end

  { resource: resource }
end
```

### Pattern 3: Soft Delete Support

```ruby
search_with do
  scope = user.admin? && params[:include_deleted] ?
    model_class.with_deleted :
    model_class

  { resource: scope.find(params[:id]) }
end
```

---

**See also:**
- [Services Structure](01_services_structure.md)
- [IndexService](02_index_service.md)
- [CreateService](04_create_service.md)
- [Service Configurations](08_service_configurations.md)
- [Cache Invalidation](../advanced/cache-invalidation.md)
