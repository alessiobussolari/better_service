# Authorization Examples

## Basic Role Check
Restrict access by user role.

```ruby
class Product::CreateService < BetterService::CreateService
  authorize_with do
    user.admin?
  end

  schema do
    required(:name).filled(:string)
  end

  process_with do |data|
    { resource: Product.create!(params) }
  end
end
```

## Permission-Based
Check specific permissions.

```ruby
class Product::DestroyService < BetterService::DestroyService
  authorize_with do
    user.has_permission?(:delete_products)
  end

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: Product.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].destroy!
    { resource: data[:resource] }
  end
end
```

## Resource Ownership
Allow access only to owners.

```ruby
class Post::UpdateService < BetterService::UpdateService
  authorize_with do
    post = Post.find(params[:id])
    post.user_id == user.id
  end

  schema do
    required(:id).filled(:integer)
    optional(:title).maybe(:string)
  end

  search_with do
    { resource: Post.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].update!(params.except(:id))
    { resource: data[:resource] }
  end
end
```

## Owner or Admin
Combine ownership with admin override.

```ruby
class Product::UpdateService < BetterService::UpdateService
  authorize_with do
    product = Product.find(params[:id])
    user.admin? || product.user_id == user.id
  end

  schema do
    required(:id).filled(:integer)
    optional(:name).maybe(:string)
  end

  search_with do
    { resource: Product.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].update!(params.except(:id))
    { resource: data[:resource] }
  end
end
```

## Status-Based Authorization
Check resource state for permissions.

```ruby
class Order::CancelService < BetterService::ActionService
  action_name :cancel

  authorize_with do
    order = Order.find(params[:id])

    # Customers can cancel own pending/confirmed orders
    if user.customer?
      order.user_id == user.id && %w[pending confirmed].include?(order.status)
    else
      # Admins can cancel any order
      user.admin?
    end
  end

  search_with do
    { resource: Order.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].update!(status: 'cancelled')
    { resource: data[:resource] }
  end
end
```

## Multiple Conditions
Complex authorization logic.

```ruby
class Article::PublishService < BetterService::ActionService
  action_name :publish

  authorize_with do
    article = Article.find(params[:id])

    # Must be draft status
    return false unless article.draft?

    # Author can publish own articles
    return true if article.author_id == user.id

    # Editors can publish any article
    return true if user.editor?

    # Admins can do anything
    return true if user.admin?

    false
  end

  search_with do
    { resource: Article.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].update!(status: 'published', published_at: Time.current)
    { resource: data[:resource] }
  end
end
```

## Team Membership
Check if user belongs to resource team.

```ruby
class Project::UpdateService < BetterService::UpdateService
  authorize_with do
    project = Project.find(params[:id])
    project.team.member?(user) || user.admin?
  end

  schema do
    required(:id).filled(:integer)
    optional(:name).maybe(:string)
  end

  search_with do
    { resource: Project.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].update!(params.except(:id))
    { resource: data[:resource] }
  end
end
```

## Conditional Field Access
Different authorization for different fields.

```ruby
class Product::UpdateService < BetterService::UpdateService
  schema do
    required(:id).filled(:integer)
    optional(:name).maybe(:string)
    optional(:price).maybe(:decimal)
    optional(:featured).maybe(:bool)
  end

  authorize_with do
    product = Product.find(params[:id])

    # Can update basic fields
    can_update_basic = user.admin? || product.user_id == user.id

    # Only admins can change featured status
    if params[:featured] && !user.admin?
      return false
    end

    can_update_basic
  end

  search_with do
    { resource: Product.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].update!(params.except(:id))
    { resource: data[:resource] }
  end
end
```

## Public Access
Allow services without authentication.

```ruby
class Article::PublicIndexService < BetterService::IndexService
  model_class Article
  self._allow_nil_user = true  # Allow nil user

  schema do
    optional(:category).maybe(:string)
  end

  search_with do
    scope = model_class.published
    scope = scope.where(category: params[:category]) if params[:category]
    { items: scope }
  end
end

# Usage without user
result = Article::PublicIndexService.new(nil, params: {}).call
```

## Subscription-Based
Check user subscription level.

```ruby
class Feature::AdvancedAnalyticsService < BetterService::IndexService
  authorize_with do
    user.subscription&.premium? || user.subscription&.enterprise?
  end

  search_with do
    { items: Analytics.advanced_data_for(user) }
  end
end
```
