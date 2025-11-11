# UpdateService Examples

## Basic Update
Update a resource with new values.

```ruby
class Product::UpdateService < BetterService::UpdateService
  model_class Product

  schema do
    required(:id).filled(:integer)
    optional(:name).maybe(:string)
    optional(:price).maybe(:decimal, gt?: 0)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    resource = data[:resource]
    resource.update!(params.except(:id))
    { resource: resource }
  end
end

# Usage
result = Product::UpdateService.new(current_user, params: {
  id: 123,
  price: 899.99
}).call
```

## With Authorization
Ensure only owner or admin can update.

```ruby
class Product::UpdateService < BetterService::UpdateService
  model_class Product

  authorize_with do
    resource = model_class.find(params[:id])
    user.admin? || resource.user_id == user.id
  end

  schema do
    required(:id).filled(:integer)
    optional(:name).maybe(:string)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    resource = data[:resource]
    resource.update!(params.except(:id))
    { resource: resource }
  end
end
```

## With Cache Invalidation
Clear caches after update.

```ruby
class Product::UpdateService < BetterService::UpdateService
  model_class Product
  cache_contexts :products, :product

  schema do
    required(:id).filled(:integer)
    optional(:name).maybe(:string)
    optional(:price).maybe(:decimal)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    resource = data[:resource]
    resource.update!(params.except(:id))

    invalidate_cache_for(user)

    { resource: resource }
  end
end
```

## Partial Update
Allow updating only specific fields.

```ruby
class User::UpdateProfileService < BetterService::UpdateService
  model_class User

  schema do
    required(:id).filled(:integer)
    optional(:first_name).maybe(:string)
    optional(:last_name).maybe(:string)
    optional(:bio).maybe(:string, max_size?: 500)
  end

  authorize_with do
    params[:id] == user.id || user.admin?
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    resource = data[:resource]
    resource.update!(params.except(:id))
    { resource: resource }
  end
end
```

## State Transition with Validation
Update status with business rules.

```ruby
class Order::UpdateStatusService < BetterService::UpdateService
  model_class Order

  schema do
    required(:id).filled(:integer)
    required(:status).filled(:string, included_in?: %w[confirmed shipped delivered])
  end

  search_with do
    order = model_class.find(params[:id])

    # Validate state transition
    unless can_transition_to?(order, params[:status])
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Cannot transition from #{order.status} to #{params[:status]}"
      )
    end

    { resource: order }
  end

  process_with do |data|
    order = data[:resource]
    order.update!(status: params[:status])

    # Send notification based on status
    OrderMailer.status_changed(order).deliver_later if order.delivered?

    { resource: order }
  end

  private

  def can_transition_to?(order, new_status)
    transitions = {
      'pending' => ['confirmed'],
      'confirmed' => ['shipped'],
      'shipped' => ['delivered']
    }
    transitions[order.status]&.include?(new_status)
  end
end
```

## With Association Updates
Update main record and associations.

```ruby
class Post::UpdateService < BetterService::UpdateService
  model_class Post

  schema do
    required(:id).filled(:integer)
    optional(:title).maybe(:string)
    optional(:content).maybe(:string)
    optional(:tag_ids).array(:integer)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    post = data[:resource]

    # Update base attributes
    post.update!(params.except(:id, :tag_ids))

    # Update associations
    post.tags = Tag.where(id: params[:tag_ids]) if params[:tag_ids]

    { resource: post }
  end
end
```

## Track Changes
Log what changed during update.

```ruby
class Product::UpdateService < BetterService::UpdateService
  model_class Product

  schema do
    required(:id).filled(:integer)
    optional(:price).maybe(:decimal)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    product = data[:resource]
    old_price = product.price

    product.update!(params.except(:id))

    # Log price change
    if old_price != product.price
      PriceHistory.create!(
        product: product,
        old_price: old_price,
        new_price: product.price,
        changed_by: user
      )
    end

    { resource: product }
  end
end
```

## Conditional Field Updates
Different fields based on user role.

```ruby
class Product::UpdateService < BetterService::UpdateService
  model_class Product

  schema do
    required(:id).filled(:integer)
    optional(:name).maybe(:string)
    optional(:price).maybe(:decimal)
    optional(:featured).maybe(:bool)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    product = data[:resource]

    # Regular users can't change featured status
    update_params = if user.admin?
      params.except(:id)
    else
      params.except(:id, :featured)
    end

    product.update!(update_params)
    { resource: product }
  end
end
```

## Optimistic Locking
Handle concurrent updates safely.

```ruby
class Document::UpdateService < BetterService::UpdateService
  model_class Document

  schema do
    required(:id).filled(:integer)
    required(:lock_version).filled(:integer)
    optional(:content).maybe(:string)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    document = data[:resource]

    begin
      document.update!(
        content: params[:content],
        lock_version: params[:lock_version]
      )
    rescue ActiveRecord::StaleObjectError
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Document was modified by another user. Please refresh and try again."
      )
    end

    { resource: document }
  end
end
```

## Batch Attribute Updates
Update multiple attributes atomically.

```ruby
class User::UpdatePreferencesService < BetterService::UpdateService
  model_class User

  schema do
    required(:id).filled(:integer)
    required(:preferences).hash do
      optional(:theme).maybe(:string)
      optional(:language).maybe(:string)
      optional(:timezone).maybe(:string)
      optional(:notifications).hash do
        optional(:email).maybe(:bool)
        optional(:sms).maybe(:bool)
        optional(:push).maybe(:bool)
      end
    end
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    user_record = data[:resource]

    # Deep merge preferences
    current_prefs = user_record.preferences || {}
    new_prefs = current_prefs.deep_merge(params[:preferences])

    user_record.update!(preferences: new_prefs)

    { resource: user_record }
  end
end
```

## Conditional Updates Based on State
Only update if current state allows it.

```ruby
class Article::PublishService < BetterService::UpdateService
  model_class Article

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    user.editor? || user.admin?
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    article = data[:resource]

    unless article.draft?
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Can only publish draft articles. Current status: #{article.status}"
      )
    end

    article.update!(
      status: 'published',
      published_at: Time.current,
      published_by_id: user.id
    )

    { resource: article }
  end
end
```

## Update with File Replacement
Remove old file and attach new one.

```ruby
class User::UpdateAvatarService < BetterService::UpdateService
  model_class User

  schema do
    required(:id).filled(:integer)
    required(:avatar).filled(:hash)
  end

  authorize_with do
    data[:resource].id == user.id || user.admin?
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    user_record = data[:resource]

    # Purge old avatar
    user_record.avatar.purge if user_record.avatar.attached?

    # Attach new avatar
    user_record.avatar.attach(params[:avatar])

    { resource: user_record }
  end
end
```

## Audit Trail Creation
Record who changed what and when.

```ruby
class Product::UpdateService < BetterService::UpdateService
  model_class Product

  schema do
    required(:id).filled(:integer)
    optional(:name).maybe(:string)
    optional(:price).maybe(:decimal)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    product = data[:resource]

    # Track changes
    changes = {}
    params.except(:id).each do |key, value|
      old_value = product.send(key)
      changes[key] = { from: old_value, to: value } if old_value != value
    end

    product.update!(params.except(:id))

    # Create audit log
    if changes.any?
      AuditLog.create!(
        auditable: product,
        user: user,
        action: 'update',
        changes: changes,
        ip_address: params[:_ip_address] # From controller
      )
    end

    { resource: product }
  end
end
```
