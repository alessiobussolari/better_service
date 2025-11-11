# DestroyService

## Overview

DestroyService is designed for deleting resources. It automatically wraps operations in database transactions, supports cache invalidation, cleanup of associations, and authorization checks.

**Characteristics:**
- **Action**: `:deleted`
- **Transaction**: Enabled (automatic rollback on errors)
- **Return Key**: `resource` (deleted object)
- **Default Schema**: `id` parameter
- **Common Use Cases**: Delete buttons, cleanup operations, cascade deletes

## Generation

### Basic Generation

```bash
rails g serviceable:destroy Product
```

This generates:

```ruby
# app/services/product/destroy_service.rb
module Product
  class DestroyService < BetterService::DestroyService
    model_class Product

    schema do
      required(:id).filled(:integer)
    end

    search_with do
      resource = model_class.find(params[:id])
      { resource: resource }
    end

    process_with do |data|
      resource = data[:resource]
      resource.destroy!
      { resource: resource }
    end
  end
end
```

### Generation with Options

```bash
# With cache invalidation
rails g serviceable:destroy Product --cache

# With authorization
rails g serviceable:destroy Product --authorize

# With specific namespace
rails g serviceable:destroy Admin::Product
```

## Schema

### Basic Schema

Requires only the ID:

```ruby
schema do
  required(:id).filled(:integer)
end
```

### With Additional Parameters

```ruby
# Soft delete with reason
schema do
  required(:id).filled(:integer)
  optional(:reason).maybe(:string)
  optional(:soft_delete).maybe(:bool)
end

# Force delete (bypass protections)
schema do
  required(:id).filled(:integer)
  optional(:force).maybe(:bool)
end

# Bulk delete
schema do
  required(:ids).array(:integer, min_size?: 1)
end
```

## Available Methods

### search_with

Loads the resource to be deleted.

**Returns**: Hash with `:resource` key containing the object.

```ruby
# Basic find
search_with do
  resource = model_class.find(params[:id])
  { resource: resource }
end

# With eager loading (to avoid N+1 in callbacks)
search_with do
  resource = model_class.includes(:associations).find(params[:id])
  { resource: resource }
end

# Check for dependent records
search_with do
  resource = model_class.find(params[:id])

  if resource.orders.any? && !params[:force]
    raise BetterService::Errors::Runtime::ValidationError.new(
      "Cannot delete product with existing orders"
    )
  end

  { resource: resource }
end
```

### process_with

Deletes the resource and performs cleanup.

**Input**: Hash from search (`:resource` key)
**Returns**: Hash with `:resource` key containing deleted object

```ruby
# Hard delete
process_with do |data|
  resource = data[:resource]
  resource.destroy!
  { resource: resource }
end

# Soft delete
process_with do |data|
  resource = data[:resource]
  resource.update!(deleted_at: Time.current, deleted_by: user)
  { resource: resource }
end

# With cleanup
process_with do |data|
  resource = data[:resource]

  # Clean up associations
  resource.images.purge_later
  resource.documents.purge_later

  # Delete dependent records
  resource.reviews.destroy_all

  # Delete the resource
  resource.destroy!

  { resource: resource }
end
```

### respond_with

Customizes the success response.

**Input**: Hash from process/transform
**Returns**: Hash with `:success`, `:message`, and data

```ruby
# Custom message
respond_with do |data|
  success_result("#{data[:resource].name} deleted successfully", data)
end

# Add metadata
respond_with do |data|
  success_result("Resource deleted", data).merge(
    deleted_at: Time.current,
    can_restore: data[:resource].respond_to?(:restore)
  )
end
```

## Configurations

### Authorization

Critical for delete operations:

```ruby
class Product::DestroyService < BetterService::DestroyService
  model_class Product

  authorize_with do
    resource = model_class.find(params[:id])

    # Only admins or owners can delete
    user.admin? || resource.user_id == user.id
  end

  process_with do |data|
    resource = data[:resource]
    resource.destroy!
    { resource: resource }
  end
end
```

### Cache Invalidation

DestroyService **automatically invalidates cache** after successful resource deletion when cache contexts are defined:

```ruby
class Product::DestroyService < BetterService::DestroyService
  model_class Product
  cache_contexts :products, :category_products

  # Auto-invalidation is ENABLED by default
  # Cache is automatically cleared after destroy completes

  process_with do |data|
    resource = data[:resource]
    resource.destroy!
    # No need to call invalidate_cache_for - it happens automatically!
    { resource: resource }
  end
end
```

**How Auto-Invalidation Works:**
1. Resource is deleted successfully
2. Transaction commits
3. Cache is automatically invalidated for all defined contexts (`:products`, `:category_products`)
4. All matching cache keys are cleared for the user

#### Disabling Auto-Invalidation

For manual control over cache invalidation:

```ruby
class Product::DestroyService < BetterService::DestroyService
  model_class Product
  cache_contexts :products, :category
  auto_invalidate_cache false  # Disable automatic invalidation

  process_with do |data|
    resource = data[:resource]
    category = resource.category
    resource.destroy!

    # Manual control: invalidate both product and category caches
    invalidate_cache_for(user)
    invalidate_cache_for(category.owner) if category.owner != user

    { resource: resource }
  end
end
```

#### Async Invalidation

Combine auto-invalidation with async for non-blocking cache clearing:

```ruby
class Product::DestroyService < BetterService::DestroyService
  model_class Product
  cache_contexts :products, :homepage
  cache_async true  # Auto-invalidation happens in background job

  process_with do |data|
    resource = data[:resource]
    resource.destroy!
    { resource: resource }
  end
end
```

## Complete Examples

### Example 1: Basic Product Deletion

```ruby
module Product
  class DestroyService < BetterService::DestroyService
    model_class Product
    cache_contexts :products

    schema do
      required(:id).filled(:integer)
    end

    authorize_with do
      resource = model_class.find(params[:id])
      user.admin? || resource.user_id == user.id
    end

    search_with do
      resource = model_class.includes(:images, :reviews).find(params[:id])

      # Check for active orders
      if resource.order_items.joins(:order).where(orders: { status: 'pending' }).any?
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Cannot delete product with pending orders"
        )
      end

      { resource: resource }
    end

    process_with do |data|
      resource = data[:resource]

      # Clean up attached files
      resource.images.purge_later

      # Delete reviews
      resource.reviews.destroy_all

      # Delete the product
      resource.destroy!

      invalidate_cache_for(user)

      { resource: resource }
    end
  end
end

# Usage
result = Product::DestroyService.new(current_user, params: { id: 123 }).call
deleted_product = result[:resource]
```

### Example 2: Soft Delete with Reason

```ruby
module Post
  class DestroyService < BetterService::DestroyService
    model_class Post
    cache_contexts :posts, :user_posts

    schema do
      required(:id).filled(:integer)
      optional(:reason).maybe(:string, included_in?: %w[spam inappropriate outdated user_request])
      optional(:permanent).maybe(:bool)
    end

    authorize_with do
      post = model_class.find(params[:id])

      # Users can soft delete own posts
      # Admins can delete any post
      # Permanent delete requires admin
      if params[:permanent]
        user.admin?
      else
        user.admin? || post.user_id == user.id
      end
    end

    search_with do
      resource = model_class.includes(:comments, :attachments).find(params[:id])
      { resource: resource }
    end

    process_with do |data|
      post = data[:resource]

      if params[:permanent]
        # Permanent deletion
        post.comments.destroy_all
        post.attachments.purge_later
        post.destroy!
      else
        # Soft deletion
        post.update!(
          deleted_at: Time.current,
          deleted_by_id: user.id,
          deletion_reason: params[:reason]
        )

        # Notify followers if published post
        if post.published?
          NotificationService.notify_post_removed(post)
        end
      end

      invalidate_cache_for(user)
      invalidate_cache_for(post.user) if post.user != user

      { resource: post }
    end

    respond_with do |data|
      message = params[:permanent] ?
        "Post permanently deleted" :
        "Post moved to trash"

      success_result(message, data).merge(
        can_restore: !params[:permanent]
      )
    end
  end
end

# Usage - Soft delete
result = Post::DestroyService.new(current_user, params: {
  id: 456,
  reason: "outdated"
}).call

# Usage - Permanent delete (admin only)
result = Post::DestroyService.new(admin_user, params: {
  id: 456,
  permanent: true
}).call
```

### Example 3: User Account Deletion

```ruby
module User
  class DeleteAccountService < BetterService::DestroyService
    model_class User
    cache_contexts :users

    schema do
      required(:id).filled(:integer)
      required(:confirmation_text).filled(:string)
      optional(:delete_content).maybe(:bool)
    end

    authorize_with do
      # Users can only delete own account or admin can delete any
      params[:id] == user.id || user.admin?
    end

    search_with do
      user_record = model_class.includes(:posts, :orders, :subscriptions).find(params[:id])

      # Require confirmation text
      unless params[:confirmation_text] == "DELETE MY ACCOUNT"
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Confirmation text does not match"
        )
      end

      # Check for active subscriptions
      if user_record.subscriptions.active.any?
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Please cancel all subscriptions before deleting account"
        )
      end

      { resource: user_record }
    end

    process_with do |data|
      user_record = data[:resource]

      # Handle user content
      if params[:delete_content]
        # Delete all user content
        user_record.posts.destroy_all
        user_record.comments.destroy_all
      else
        # Anonymize user content
        anonymized_name = "Deleted User #{user_record.id}"
        user_record.posts.update_all(user_id: nil, author_name: anonymized_name)
        user_record.comments.update_all(user_id: nil, author_name: anonymized_name)
      end

      # Cancel pending orders
      # Note: For complex multi-step operations like this, consider using a workflow
      # instead of calling services from within services
      user_record.orders.pending.update_all(status: 'cancelled', cancelled_at: Time.current)

      # Remove from mailing lists
      MailingListService.unsubscribe(user_record.email)

      # Purge uploaded files
      user_record.avatar.purge_later if user_record.avatar.attached?

      # Send farewell email
      UserMailer.account_deleted(user_record.email).deliver_later

      # Delete the account
      user_record.destroy!

      invalidate_cache_for(user)

      { resource: user_record }
    end

    respond_with do |data|
      success_result("Account deleted successfully", data).merge(
        content_deleted: params[:delete_content],
        email: data[:resource].email  # For confirmation
      )
    end
  end
end

# Usage
result = User::DeleteAccountService.new(current_user, params: {
  id: current_user.id,
  confirmation_text: "DELETE MY ACCOUNT",
  delete_content: true
}).call
```

### Example 4: Bulk Delete

```ruby
module Product
  class BulkDestroyService < BetterService::DestroyService
    model_class Product
    cache_contexts :products

    schema do
      required(:ids).array(:integer, min_size?: 1, max_size?: 100)
      optional(:skip_errors).maybe(:bool)
    end

    authorize_with do
      user.admin? || user.has_permission?(:bulk_delete_products)
    end

    search_with do
      products = model_class.where(id: params[:ids])

      if products.count != params[:ids].count
        missing = params[:ids] - products.pluck(:id)
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Products not found: #{missing.join(', ')}"
        )
      end

      # Check for products with active orders
      products_with_orders = products.joins(:order_items)
        .where(order_items: { status: 'active' })
        .distinct

      if products_with_orders.any? && !params[:skip_errors]
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Some products have active orders. Use skip_errors to ignore."
        )
      end

      { resources: products, protected: products_with_orders.pluck(:id) }
    end

    process_with do |data|
      products = data[:resources]
      protected_ids = data[:protected]

      deleted = []
      skipped = []
      errors = []

      products.each do |product|
        begin
          # Skip protected products if skip_errors is true
          if protected_ids.include?(product.id) && params[:skip_errors]
            skipped << product.id
            next
          end

          # Clean up
          product.images.purge_later
          product.reviews.destroy_all

          # Delete
          product.destroy!

          deleted << product.id
        rescue => e
          if params[:skip_errors]
            errors << { id: product.id, error: e.message }
          else
            raise
          end
        end
      end

      invalidate_cache_for(user)

      {
        resource: products,
        metadata: {
          deleted: deleted,
          skipped: skipped,
          errors: errors,
          total: products.count
        }
      }
    end

    respond_with do |data|
      meta = data[:metadata]
      message = "Deleted #{meta[:deleted].count}/#{meta[:total]} products"

      success_result(message, data)
    end
  end
end

# Usage
result = Product::BulkDestroyService.new(current_user, params: {
  ids: [1, 2, 3, 4, 5],
  skip_errors: true
}).call

puts result[:metadata]
# => {
#   deleted: [1, 2, 5],
#   skipped: [3],
#   errors: [{ id: 4, error: "..." }],
#   total: 5
# }
```

## Best Practices

### 1. Always Authorize Deletions

```ruby
# ✅ Critical: Authorization for deletes
authorize_with do
  resource = model_class.find(params[:id])

  # Be strict about who can delete
  user.admin? || (resource.user_id == user.id && resource.can_be_deleted?)
end
```

### 2. Check Dependencies Before Deleting

```ruby
search_with do
  resource = model_class.find(params[:id])

  # Check for dependencies
  if resource.has_dependent_records? && !params[:force]
    raise BetterService::Errors::Runtime::ValidationError.new(
      "Resource has dependent records. Use force to delete anyway."
    )
  end

  { resource: resource }
end
```

### 3. Clean Up Associated Resources

```ruby
process_with do |data|
  resource = data[:resource]

  # Clean up files
  resource.images.purge_later
  resource.documents.purge_later

  # Clean up cache entries
  Rails.cache.delete("resource:#{resource.id}")

  # Cancel scheduled jobs
  resource.scheduled_jobs.each(&:cancel)

  # Delete the resource
  resource.destroy!

  { resource: resource }
end
```

### 4. Use Soft Deletes When Appropriate

```ruby
# For user-facing content, prefer soft delete
process_with do |data|
  resource = data[:resource]

  # Soft delete keeps data for recovery
  resource.update!(
    deleted_at: Time.current,
    deleted_by_id: user.id
  )

  { resource: resource }
end

# Provide restore service
module Post
  class RestoreService < BetterService::UpdateService
    schema do
      required(:id).filled(:integer)
    end

    search_with do
      { resource: model_class.with_deleted.find(params[:id]) }
    end

    process_with do |data|
      data[:resource].update!(deleted_at: nil, deleted_by_id: nil)
      { resource: data[:resource] }
    end
  end
end
```

### 5. Log Deletions

```ruby
process_with do |data|
  resource = data[:resource]

  # Create audit log
  AuditLog.create!(
    action: 'delete',
    resource_type: resource.class.name,
    resource_id: resource.id,
    resource_data: resource.attributes,
    user: user
  )

  resource.destroy!

  { resource: resource }
end
```

### 6. Use Transactions for Complex Deletions

```ruby
# Transactions are enabled by default
process_with do |data|
  resource = data[:resource]

  # All of this happens in a transaction
  resource.order_items.destroy_all
  resource.reviews.destroy_all
  resource.images.purge_later
  resource.destroy!

  # If anything fails, everything rolls back

  { resource: resource }
end
```

## Testing

### RSpec

```ruby
# spec/services/product/destroy_service_spec.rb
require 'rails_helper'

RSpec.describe Product::DestroyService do
  let(:user) { create(:user, :admin) }
  let(:product) { create(:product) }

  describe '#call' do
    it 'deletes the product' do
      expect {
        described_class.new(user, params: { id: product.id }).call
      }.to change(Product, :count).by(-1)
    end

    it 'returns the deleted product' do
      result = described_class.new(user, params: { id: product.id }).call

      expect(result[:success]).to be true
      expect(result[:resource].id).to eq(product.id)
      expect(result[:resource]).to be_destroyed
    end

    it 'deletes associated records' do
      create_list(:review, 3, product: product)

      expect {
        described_class.new(user, params: { id: product.id }).call
      }.to change(Review, :count).by(-3)
    end

    context 'when product does not exist' do
      it 'raises RecordNotFound error' do
        expect {
          described_class.new(user, params: { id: 99999 }).call
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'with dependencies' do
      let!(:order_item) { create(:order_item, product: product) }

      it 'prevents deletion if product has orders' do
        expect {
          described_class.new(user, params: { id: product.id }).call
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end

      it 'allows force deletion' do
        expect {
          described_class.new(user, params: { id: product.id, force: true }).call
        }.to change(Product, :count).by(-1)
      end
    end

    context 'authorization' do
      let(:owner) { create(:user) }
      let(:other_user) { create(:user) }
      let(:product) { create(:product, user: owner) }

      it 'allows owner to delete' do
        expect {
          described_class.new(owner, params: { id: product.id }).call
        }.to change(Product, :count).by(-1)
      end

      it 'denies other users from deleting' do
        expect {
          described_class.new(other_user, params: { id: product.id }).call
        }.to raise_error(BetterService::Errors::Runtime::AuthorizationError)
      end
    end

    context 'cache invalidation' do
      it 'invalidates product caches' do
        expect(Rails.cache).to receive(:delete_matched).with(/products/)

        described_class.new(user, params: { id: product.id }).call
      end
    end

    context 'transactions' do
      it 'rolls back on error' do
        allow_any_instance_of(Product).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed)

        expect {
          described_class.new(user, params: { id: product.id }).call rescue nil
        }.not_to change(Product, :count)
      end
    end
  end
end
```

### Minitest

```ruby
# test/services/product/destroy_service_test.rb
require 'test_helper'

class Product::DestroyServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @product = products(:laptop)
  end

  test "deletes the product" do
    assert_difference 'Product.count', -1 do
      Product::DestroyService.new(@user, params: { id: @product.id }).call
    end
  end

  test "returns deleted product" do
    result = Product::DestroyService.new(@user, params: { id: @product.id }).call

    assert result[:success]
    assert_equal @product.id, result[:resource].id
    assert result[:resource].destroyed?
  end

  test "raises error when product not found" do
    assert_raises ActiveRecord::RecordNotFound do
      Product::DestroyService.new(@user, params: { id: 99999 }).call
    end
  end

  test "prevents deletion with dependencies" do
    create(:order_item, product: @product)

    assert_raises BetterService::Errors::Runtime::ValidationError do
      Product::DestroyService.new(@user, params: { id: @product.id }).call
    end
  end

  test "denies unauthorized deletion" do
    regular_user = users(:regular)

    assert_raises BetterService::Errors::Runtime::AuthorizationError do
      Product::DestroyService.new(regular_user, params: { id: @product.id }).call
    end
  end

  test "rolls back on error" do
    Product.any_instance.stubs(:destroy!).raises(ActiveRecord::RecordNotDestroyed)

    assert_no_difference 'Product.count' do
      Product::DestroyService.new(@user, params: { id: @product.id }).call rescue nil
    end
  end
end
```

## Common Patterns

### Pattern 1: Cascade Delete

```ruby
process_with do |data|
  resource = data[:resource]

  # Delete in order
  resource.order_items.destroy_all
  resource.reviews.destroy_all
  resource.comments.destroy_all
  resource.destroy!

  { resource: resource }
end
```

### Pattern 2: Archive Instead of Delete

```ruby
process_with do |data|
  resource = data[:resource]

  # Move to archive table
  Archive.create!(
    resource_type: resource.class.name,
    resource_id: resource.id,
    data: resource.attributes,
    archived_by: user
  )

  resource.destroy!

  { resource: resource }
end
```

### Pattern 3: Conditional Soft/Hard Delete

```ruby
process_with do |data|
  resource = data[:resource]

  if resource.created_at > 30.days.ago || params[:soft]
    # Soft delete recent items
    resource.update!(deleted_at: Time.current)
  else
    # Hard delete old items
    resource.destroy!
  end

  { resource: resource }
end
```

---

**See also:**
- [Services Structure](01_services_structure.md)
- [CreateService](04_create_service.md)
- [UpdateService](05_update_service.md)
- [Service Configurations](08_service_configurations.md)
- [Error Handling](../advanced/error-handling.md)
