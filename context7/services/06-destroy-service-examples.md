# DestroyService Examples

## Basic Deletion
Delete a resource by ID.

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
    resource.destroy!
    { resource: resource }
  end
end

# Usage
result = Product::DestroyService.new(current_user, params: { id: 123 }).call
```

## With Authorization
Ensure only owner or admin can delete.

```ruby
class Post::DestroyService < BetterService::DestroyService
  model_class Post

  authorize_with do
    resource = model_class.find(params[:id])
    user.admin? || resource.user_id == user.id
  end

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    resource = data[:resource]
    resource.destroy!
    { resource: resource }
  end
end
```

## With Dependency Check
Prevent deletion if dependencies exist.

```ruby
class Product::DestroyService < BetterService::DestroyService
  model_class Product

  schema do
    required(:id).filled(:integer)
    optional(:force).maybe(:bool)
  end

  search_with do
    product = model_class.find(params[:id])

    # Check for active orders
    if product.order_items.joins(:order).where(orders: { status: 'active' }).any?
      unless params[:force]
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Cannot delete product with active orders"
        )
      end
    end

    { resource: product }
  end

  process_with do |data|
    resource = data[:resource]
    resource.destroy!
    { resource: resource }
  end
end
```

## With Cleanup
Remove associated resources before deletion.

```ruby
class Product::DestroyService < BetterService::DestroyService
  model_class Product
  cache_contexts :products

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.includes(:images, :reviews).find(params[:id]) }
  end

  process_with do |data|
    product = data[:resource]

    # Clean up associations
    product.images.purge_later
    product.reviews.destroy_all

    # Delete the product
    product.destroy!

    invalidate_cache_for(user)

    { resource: product }
  end
end
```

## Soft Delete
Mark as deleted instead of removing from database.

```ruby
class Post::DestroyService < BetterService::DestroyService
  model_class Post

  schema do
    required(:id).filled(:integer)
    optional(:reason).maybe(:string)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    post = data[:resource]

    # Soft delete
    post.update!(
      deleted_at: Time.current,
      deleted_by_id: user.id,
      deletion_reason: params[:reason]
    )

    { resource: post }
  end
end
```

## With Audit Log
Log deletion for compliance.

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
    product = data[:resource]

    # Create audit log before deletion
    AuditLog.create!(
      action: 'delete',
      resource_type: 'Product',
      resource_id: product.id,
      resource_data: product.attributes,
      user: user
    )

    product.destroy!

    { resource: product }
  end
end
```

## Conditional Soft/Hard Delete
Different behavior based on age.

```ruby
class Order::DestroyService < BetterService::DestroyService
  model_class Order

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    order = data[:resource]

    if order.created_at > 30.days.ago
      # Recent orders: soft delete
      order.update!(deleted_at: Time.current, deleted_by: user)
    else
      # Old orders: hard delete
      order.destroy!
    end

    { resource: order }
  end
end
```

## Cascade Delete with Children
Delete resource and all related records.

```ruby
class Project::DestroyService < BetterService::DestroyService
  model_class Project

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    project = model_class.find(params[:id])
    project.user_id == user.id || user.admin?
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    project = data[:resource]

    # Manually cascade delete (or use dependent: :destroy in model)
    project.tasks.destroy_all
    project.documents.destroy_all
    project.comments.destroy_all

    project.destroy!

    { resource: project }
  end
end
```

## Archive Instead of Delete
Move to archive table for data retention.

```ruby
class Document::DestroyService < BetterService::DestroyService
  model_class Document

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    document = data[:resource]

    # Create archive record
    ArchivedDocument.create!(
      document.attributes.merge(
        archived_at: Time.current,
        archived_by_id: user.id,
        original_id: document.id
      )
    )

    # Hard delete original
    document.destroy!

    { resource: document }
  end
end
```

## Delete with External Cleanup
Remove associated files from cloud storage.

```ruby
class Media::DestroyService < BetterService::DestroyService
  model_class Media

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    media = data[:resource]

    # Remove from S3/cloud storage
    if media.file.attached?
      media.file.purge
    end

    # Invalidate CDN cache
    begin
      CdnService.invalidate_cache(media.cdn_url)
    rescue StandardError => e
      Rails.logger.error("CDN invalidation failed: #{e.message}")
    end

    media.destroy!

    { resource: media }
  end
end
```

## Scheduled Deletion
Mark for deletion and process later.

```ruby
class Account::DestroyService < BetterService::DestroyService
  model_class Account

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    account = data[:resource]

    # Schedule deletion for 30 days from now
    account.update!(
      deletion_scheduled_at: 30.days.from_now,
      deletion_requested_by_id: user.id,
      status: 'pending_deletion'
    )

    # Send notification
    AccountMailer.deletion_scheduled(account).deliver_later

    { resource: account }
  end
end

# Background job to process scheduled deletions:
# DeleteScheduledAccountsJob.perform_later
```

## Restore from Soft Delete
Undelete a soft-deleted record.

```ruby
class Post::RestoreService < BetterService::ActionService
  model_class Post
  action_name :restore

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    user.admin? || user.moderator?
  end

  search_with do
    # Find soft-deleted post
    resource = model_class.where.not(deleted_at: nil).find(params[:id])
    { resource: resource }
  end

  process_with do |data|
    post = data[:resource]

    post.update!(
      deleted_at: nil,
      deleted_by_id: nil,
      deletion_reason: nil,
      restored_at: Time.current,
      restored_by_id: user.id
    )

    { resource: post }
  end
end
```
