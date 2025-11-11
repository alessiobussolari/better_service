# ShowService Examples

## Basic Show
Retrieve a single record by ID.

```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end
end

# Usage
result = Product::ShowService.new(current_user, params: { id: 123 }).call
product = result[:resource]
```

## With Eager Loading
Load associations to avoid N+1 queries.

```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    resource = model_class
      .includes(:category, :reviews, :images)
      .find(params[:id])

    { resource: resource }
  end
end
```

## With Authorization
Ensure user can access the resource.

```ruby
class Post::ShowService < BetterService::ShowService
  model_class Post

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    post = model_class.find(params[:id])
    post.public? || post.user_id == user.id || user.admin?
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end
end
```

## With Cache
Cache frequently accessed resources.

```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product
  cache_contexts :product

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.includes(:category).find(params[:id]) }
  end
end
```

## With Presenter
Format the resource for output.

```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product
  presenter ProductPresenter

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.includes(:category, :reviews).find(params[:id]) }
  end
end
```

## By Slug Instead of ID
Find resource by slug field.

```ruby
class Article::ShowBySlugService < BetterService::ShowService
  model_class Article

  schema do
    required(:slug).filled(:string)
  end

  search_with do
    resource = model_class.find_by!(slug: params[:slug])
    { resource: resource }
  end
end

# Usage
result = Article::ShowBySlugService.new(current_user, params: {
  slug: 'getting-started'
}).call
```

## Track View Count
Increment views when resource is accessed.

```ruby
class Article::ShowService < BetterService::ShowService
  model_class Article

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    article = data[:resource]
    article.increment!(:view_count) unless article.user_id == user.id
    { resource: article }
  end
end
```

## With Metadata
Add related data to the response.

```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    product = data[:resource]

    {
      resource: product,
      related_products: Product
        .where(category_id: product.category_id)
        .where.not(id: product.id)
        .limit(5)
    }
  end
end
```

## For Public Access
Allow nil user for public resources.

```ruby
class Article::PublicShowService < BetterService::ShowService
  model_class Article
  self._allow_nil_user = true

  schema do
    required(:slug).filled(:string)
  end

  search_with do
    resource = model_class.published.find_by!(slug: params[:slug])
    { resource: resource }
  end
end

# Usage without user
result = Article::PublicShowService.new(nil, params: { slug: 'post' }).call
```

## Show Specific Version
Display a historical version of a record.

```ruby
class Document::ShowVersionService < BetterService::ShowService
  model_class Document

  schema do
    required(:id).filled(:integer)
    optional(:version).maybe(:integer)
  end

  search_with do
    document = model_class.find(params[:id])

    # Use paper_trail or similar versioning gem
    resource = if params[:version]
                 document.versions.find_by(version: params[:version])&.reify || document
               else
                 document
               end

    { resource: resource }
  end
end
```

## Draft vs Published View
Show different data based on publication status.

```ruby
class Article::ShowService < BetterService::ShowService
  model_class Article

  schema do
    required(:id).filled(:integer)
    optional(:preview).maybe(:bool)
  end

  authorize_with do
    article = model_class.find(params[:id])

    # Allow preview for authors/editors
    if params[:preview]
      article.user_id == user.id || user.editor?
    else
      article.published?
    end
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  respond_with do |data|
    article = data[:resource]

    {
      resource: {
        id: article.id,
        title: article.title,
        content: params[:preview] ? article.draft_content : article.published_content,
        status: article.status,
        published_at: article.published_at
      }
    }
  end
end
```

## Polymorphic Resource Lookup
Find resource by multiple identifier types.

```ruby
class User::ShowService < BetterService::ShowService
  model_class User

  schema do
    optional(:id).maybe(:integer)
    optional(:email).maybe(:string)
    optional(:username).maybe(:string)
  end

  search_with do
    resource = if params[:id]
                 model_class.find(params[:id])
               elsif params[:email]
                 model_class.find_by!(email: params[:email])
               elsif params[:username]
                 model_class.find_by!(username: params[:username])
               else
                 raise "Must provide id, email, or username"
               end

    { resource: resource }
  end
end

# Usage
User::ShowService.new(user, params: { email: 'user@example.com' }).call
User::ShowService.new(user, params: { username: 'john_doe' }).call
```

## With Aggregated Statistics
Include computed statistics and related data.

```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.includes(:reviews, :category).find(params[:id]) }
  end

  process_with do |data|
    product = data[:resource]

    {
      resource: product,
      statistics: {
        total_reviews: product.reviews.count,
        average_rating: product.reviews.average(:rating)&.round(2),
        total_sales: product.order_items.sum(:quantity),
        revenue: product.order_items.sum('quantity * price')
      },
      related_products: Product
        .where(category_id: product.category_id)
        .where.not(id: product.id)
        .order(popularity: :desc)
        .limit(5)
    }
  end
end
```

## Multi-Tenant Scoped Show
Ensure tenant isolation when showing resource.

```ruby
class Order::ShowService < BetterService::ShowService
  model_class Order

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    # Ensure order belongs to current user's tenant
    order = model_class.find(params[:id])
    order.tenant_id == user.tenant_id
  end

  search_with do
    # Scope to current tenant
    resource = user.tenant.orders.includes(:items, :customer).find(params[:id])
    { resource: resource }
  end
end
```
