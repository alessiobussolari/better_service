# Common Patterns Examples

## Soft Delete Pattern
Mark records as deleted instead of removing.

```ruby
class Product::DestroyService < BetterService::DestroyService
  model_class Product

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    resource = data[:resource]
    resource.update!(deleted_at: Time.current)
    { resource: resource }
  end
end
```

## Slug Generation Pattern
Auto-generate URL-friendly slugs.

```ruby
class Article::CreateService < BetterService::CreateService
  model_class Article

  schema do
    required(:title).filled(:string)
    required(:content).filled(:string)
  end

  process_with do |data|
    slug = params[:title].parameterize
    resource = model_class.create!(
      params.merge(slug: slug)
    )
    { resource: resource }
  end
end
```

## Owner Assignment Pattern
Assign current user as owner.

```ruby
class Document::CreateService < BetterService::CreateService
  model_class Document

  schema do
    required(:title).filled(:string)
    required(:content).filled(:string)
  end

  process_with do |data|
    resource = model_class.create!(
      params.merge(user_id: user.id)
    )
    { resource: resource }
  end
end
```

## Timestamp Tracking Pattern
Track who created/updated records.

```ruby
class Post::UpdateService < BetterService::UpdateService
  model_class Post

  schema do
    required(:id).filled(:integer)
    optional(:title).filled(:string)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    resource = data[:resource]
    resource.update!(
      params.except(:id).merge(
        updated_by_id: user.id,
        updated_at: Time.current
      )
    )
    { resource: resource }
  end
end
```

## Status Transition Pattern
Change status with validation.

```ruby
class Order::ApproveService < BetterService::ActionService
  model_class Order
  action_name :approve

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    user.admin? || user.manager?
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    resource = data[:resource]
    raise "Cannot approve #{resource.status} order" unless resource.pending?

    resource.update!(
      status: 'approved',
      approved_by_id: user.id,
      approved_at: Time.current
    )
    { resource: resource }
  end
end
```

## Bulk Operations Pattern
Process multiple records at once.

```ruby
class Product::BulkUpdateService < BetterService::ActionService
  model_class Product
  action_name :bulk_update

  schema do
    required(:ids).filled(:array)
    required(:attributes).hash
  end

  authorize_with do
    user.admin?
  end

  search_with do
    { resources: model_class.where(id: params[:ids]) }
  end

  process_with do |data|
    resources = data[:resources]
    resources.update_all(params[:attributes])
    { resources: resources.reload }
  end
end
```

## Duplicate Detection Pattern
Prevent duplicate records.

```ruby
class Contact::CreateService < BetterService::CreateService
  model_class Contact

  schema do
    required(:email).filled(:string)
    required(:name).filled(:string)
  end

  process_with do |data|
    existing = model_class.find_by(
      email: params[:email],
      user_id: user.id
    )

    raise "Contact already exists" if existing

    resource = model_class.create!(
      params.merge(user_id: user.id)
    )
    { resource: resource }
  end
end
```

## Counter Cache Pattern
Update counters after operations.

```ruby
class Comment::CreateService < BetterService::CreateService
  model_class Comment

  schema do
    required(:post_id).filled(:integer)
    required(:content).filled(:string)
  end

  process_with do |data|
    resource = model_class.create!(
      params.merge(user_id: user.id)
    )

    # Update counter
    resource.post.increment!(:comments_count)

    { resource: resource }
  end
end
```

## File Upload Pattern
Handle file attachments.

```ruby
class Avatar::UpdateService < BetterService::UpdateService
  model_class User

  schema do
    required(:id).filled(:integer)
    required(:avatar).filled(:hash)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  authorize_with do
    data[:resource].id == user.id || user.admin?
  end

  process_with do |data|
    resource = data[:resource]
    resource.avatar.attach(params[:avatar])
    { resource: resource }
  end
end
```

## Search with Filters Pattern
Filter list by multiple criteria.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  schema do
    optional(:category_id).maybe(:integer)
    optional(:min_price).maybe(:float)
    optional(:max_price).maybe(:float)
    optional(:search).maybe(:string)
  end

  search_with do
    scope = model_class.all

    scope = scope.where(category_id: params[:category_id]) if params[:category_id]
    scope = scope.where('price >= ?', params[:min_price]) if params[:min_price]
    scope = scope.where('price <= ?', params[:max_price]) if params[:max_price]
    scope = scope.where('name ILIKE ?', "%#{params[:search]}%") if params[:search]

    { items: scope }
  end
end
```
