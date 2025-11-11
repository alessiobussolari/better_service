# UpdateService

## Overview

UpdateService is designed for modifying existing resources. It automatically wraps operations in database transactions, supports cache invalidation, partial updates, and authorization checks.

**Characteristics:**
- **Action**: `:updated`
- **Transaction**: Enabled (automatic rollback on errors)
- **Return Key**: `resource` (updated object)
- **Default Schema**: `id` + update fields
- **Common Use Cases**: Edit forms, PATCH endpoints, resource modifications

## Generation

### Basic Generation

```bash
rails g serviceable:update Product
```

This generates:

```ruby
# app/services/product/update_service.rb
module Product
  class UpdateService < BetterService::UpdateService
    model_class Product

    schema do
      required(:id).filled(:integer)
      # Add your updateable fields
      optional(:name).maybe(:string)
      optional(:price).maybe(:decimal)
    end

    search_with do
      resource = model_class.find(params[:id])
      { resource: resource }
    end

    process_with do |data|
      resource = data[:resource]
      resource.update!(params.except(:id))
      { resource: resource }
    end
  end
end
```

### Generation with Options

```bash
# With cache invalidation
rails g serviceable:update Product --cache

# With authorization
rails g serviceable:update Product --authorize

# With specific namespace
rails g serviceable:update Admin::Product
```

## Schema

### Basic Schema

Require ID and define updateable fields:

```ruby
schema do
  required(:id).filled(:integer)

  # All fields optional for partial updates
  optional(:name).maybe(:string)
  optional(:price).maybe(:decimal, gt?: 0)
  optional(:description).maybe(:string)
  optional(:category_id).maybe(:integer)
  optional(:status).maybe(:string, included_in?: %w[active inactive])
end
```

### Partial vs Full Updates

```ruby
# Partial update (most common)
schema do
  required(:id).filled(:integer)
  optional(:name).maybe(:string)
  optional(:price).maybe(:decimal)
  # Any combination of fields can be updated
end

# Full replacement (less common)
schema do
  required(:id).filled(:integer)
  required(:name).filled(:string)  # Must provide all fields
  required(:price).filled(:decimal)
  required(:description).filled(:string)
end
```

### Conditional Validations

```ruby
schema do
  required(:id).filled(:integer)
  optional(:status).maybe(:string, included_in?: %w[draft published archived])
  optional(:published_at).maybe(:time)

  # Require published_at when status is 'published'
  rule(:status, :published_at) do
    if values[:status] == 'published' && values[:published_at].nil?
      key(:published_at).failure('must be present when publishing')
    end
  end
end
```

## Available Methods

### search_with

Loads the resource to be updated.

**Returns**: Hash with `:resource` key containing the object.

```ruby
# Basic find
search_with do
  resource = model_class.find(params[:id])
  { resource: resource }
end

# With eager loading
search_with do
  resource = model_class.includes(:category, :tags).find(params[:id])
  { resource: resource }
end

# Find by different identifier
search_with do
  resource = model_class.find_by!(slug: params[:slug])
  { resource: resource }
end

# With soft delete support
search_with do
  scope = user.admin? ? model_class.with_deleted : model_class
  { resource: scope.find(params[:id]) }
end
```

### process_with

Updates the resource and performs business logic.

**Input**: Hash from search (`:resource` key)
**Returns**: Hash with `:resource` key containing updated object

```ruby
# Basic update
process_with do |data|
  resource = data[:resource]
  resource.update!(params.except(:id))
  { resource: resource }
end

# Track changes
process_with do |data|
  resource = data[:resource]
  old_status = resource.status

  resource.update!(params.except(:id))

  # Log status change
  if old_status != resource.status
    StatusChangeLog.create!(
      resource: resource,
      from: old_status,
      to: resource.status,
      changed_by: user
    )
  end

  { resource: resource }
end

# Handle associations
process_with do |data|
  resource = data[:resource]

  # Update base attributes
  resource.update!(params.except(:id, :tag_ids))

  # Update associations
  if params[:tag_ids]
    resource.tags = Tag.where(id: params[:tag_ids])
  end

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
  success_result("#{data[:resource].name} updated successfully", data)
end

# Include change summary
respond_with do |data|
  changes = data[:resource].previous_changes.keys
  message = "Updated: #{changes.join(', ')}"

  success_result(message, data)
end
```

## Configurations

### Authorization

Ensure user can update the resource:

```ruby
class Product::UpdateService < BetterService::UpdateService
  model_class Product

  authorize_with do
    resource = model_class.find(params[:id])

    # Only admins or owners can update
    user.admin? || resource.user_id == user.id
  end

  process_with do |data|
    resource = data[:resource]
    resource.update!(params.except(:id))
    { resource: resource }
  end
end
```

### Cache Invalidation

UpdateService **automatically invalidates cache** after successful resource update when cache contexts are defined:

```ruby
class Product::UpdateService < BetterService::UpdateService
  model_class Product
  cache_contexts :products, :product_details

  # Auto-invalidation is ENABLED by default
  # Cache is automatically cleared after update completes

  process_with do |data|
    resource = data[:resource]
    resource.update!(params.except(:id))
    # No need to call invalidate_cache_for - it happens automatically!
    { resource: resource }
  end
end
```

**How Auto-Invalidation Works:**
1. Resource is updated successfully
2. Transaction commits
3. Cache is automatically invalidated for all defined contexts (`:products`, `:product_details`)
4. All matching cache keys are cleared for the user

#### Disabling Auto-Invalidation

For manual control over cache invalidation:

```ruby
class Product::UpdateService < BetterService::UpdateService
  model_class Product
  cache_contexts :products
  auto_invalidate_cache false  # Disable automatic invalidation

  process_with do |data|
    resource = data[:resource]
    old_price = resource.price
    resource.update!(params.except(:id))

    # Manual control: only invalidate if price changed
    invalidate_cache_for(user) if resource.price != old_price

    { resource: resource }
  end
end
```

#### Async Invalidation

Combine auto-invalidation with async for non-blocking cache clearing:

```ruby
class Product::UpdateService < BetterService::UpdateService
  model_class Product
  cache_contexts :products, :homepage
  cache_async true  # Auto-invalidation happens in background job

  process_with do |data|
    resource = data[:resource]
    resource.update!(params.except(:id))
    { resource: resource }
  end
end
```

### Presenter Configuration

Format the updated resource:

```ruby
class Product::UpdateService < BetterService::UpdateService
  model_class Product
  presenter ProductPresenter

  process_with do |data|
    resource = data[:resource]
    resource.update!(params.except(:id))
    { resource: resource }
  end
end
```

## Complete Examples

### Example 1: Basic Product Update

```ruby
module Product
  class UpdateService < BetterService::UpdateService
    model_class Product
    cache_contexts :products, :product

    schema do
      required(:id).filled(:integer)
      optional(:name).maybe(:string)
      optional(:price).maybe(:decimal, gt?: 0)
      optional(:description).maybe(:string)
      optional(:category_id).maybe(:integer)
    end

    authorize_with do
      resource = model_class.find(params[:id])
      user.admin? || resource.user_id == user.id
    end

    search_with do
      resource = model_class.includes(:category).find(params[:id])
      { resource: resource }
    end

    process_with do |data|
      resource = data[:resource]
      resource.update!(params.except(:id))

      invalidate_cache_for(user)

      { resource: resource }
    end
  end
end

# Usage
result = Product::UpdateService.new(current_user, params: {
  id: 123,
  name: "Updated Product Name",
  price: 999.99
}).call

product = result[:resource]
```

### Example 2: Status Transition with Validation

```ruby
module Order
  class UpdateStatusService < BetterService::UpdateService
    model_class Order
    cache_contexts :orders, :user_orders

    VALID_TRANSITIONS = {
      'pending' => ['confirmed', 'cancelled'],
      'confirmed' => ['shipped', 'cancelled'],
      'shipped' => ['delivered', 'returned'],
      'delivered' => ['returned'],
      'cancelled' => [],
      'returned' => []
    }

    schema do
      required(:id).filled(:integer)
      required(:status).filled(:string, included_in?: VALID_TRANSITIONS.keys)
      optional(:cancellation_reason).maybe(:string)
      optional(:tracking_number).maybe(:string)
    end

    authorize_with do
      order = model_class.find(params[:id])

      # Customers can only cancel their own pending/confirmed orders
      if user.customer?
        order.user_id == user.id &&
          params[:status] == 'cancelled' &&
          ['pending', 'confirmed'].include?(order.status)
      else
        # Admins can perform any transition
        user.admin?
      end
    end

    search_with do
      order = model_class.includes(:items, :user).find(params[:id])
      { resource: order }
    end

    process_with do |data|
      order = data[:resource]
      old_status = order.status
      new_status = params[:status]

      # Validate transition
      unless VALID_TRANSITIONS[old_status]&.include?(new_status)
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Cannot transition from #{old_status} to #{new_status}"
        )
      end

      # Specific validations per status
      case new_status
      when 'shipped'
        unless params[:tracking_number].present?
          raise BetterService::Errors::Runtime::ValidationError.new(
            "Tracking number required for shipment"
          )
        end
      when 'cancelled'
        unless params[:cancellation_reason].present?
          raise BetterService::Errors::Runtime::ValidationError.new(
            "Cancellation reason required"
          )
        end
      end

      # Update order
      order.update!(
        status: new_status,
        tracking_number: params[:tracking_number],
        cancellation_reason: params[:cancellation_reason]
      )

      # Log status change
      order.status_logs.create!(
        from_status: old_status,
        to_status: new_status,
        changed_by: user,
        notes: params[:cancellation_reason] || params[:tracking_number]
      )

      # Perform status-specific actions
      case new_status
      when 'shipped'
        OrderMailer.shipped(order).deliver_later
      when 'delivered'
        OrderMailer.delivered(order).deliver_later
        # Create review request after 3 days
        ReviewRequestJob.set(wait: 3.days).perform_later(order.id)
      when 'cancelled'
        # Restore product stock
        order.items.each do |item|
          item.product.increment!(:stock, item.quantity)
        end
        # Refund payment
        PaymentRefundJob.perform_later(order.id)
        OrderMailer.cancelled(order).deliver_later
      end

      invalidate_cache_for(user)
      invalidate_cache_for(order.user) if order.user != user

      { resource: order }
    end
  end
end

# Usage
result = Order::UpdateStatusService.new(current_user, params: {
  id: 456,
  status: 'shipped',
  tracking_number: 'TRACK123456'
}).call
```

### Example 3: Profile Update with Image

```ruby
module User
  class UpdateProfileService < BetterService::UpdateService
    model_class User
    cache_contexts :user_profile
    presenter UserPresenter

    schema do
      required(:id).filled(:integer)
      optional(:first_name).maybe(:string)
      optional(:last_name).maybe(:string)
      optional(:bio).maybe(:string, max_size?: 500)
      optional(:avatar).maybe(:hash)
      optional(:social_links).maybe(:hash) do
        optional(:twitter).maybe(:string)
        optional(:linkedin).maybe(:string)
        optional(:github).maybe(:string)
      end
    end

    authorize_with do
      # Users can only update their own profile, or admins
      params[:id] == user.id || user.admin?
    end

    search_with do
      resource = model_class.find(params[:id])
      { resource: resource }
    end

    process_with do |data|
      user_record = data[:resource]

      # Update basic fields
      user_record.update!(
        params.except(:id, :avatar, :social_links)
      )

      # Update avatar if provided
      if params[:avatar]
        user_record.avatar.purge if user_record.avatar.attached?
        user_record.avatar.attach(params[:avatar])
      end

      # Update social links
      if params[:social_links]
        user_record.profile.update!(
          social_links: params[:social_links]
        )
      end

      # Update search index
      user_record.reindex_for_search

      invalidate_cache_for(user)

      { resource: user_record }
    end
  end
end

# Usage
result = User::UpdateProfileService.new(current_user, params: {
  id: current_user.id,
  first_name: "John",
  bio: "Software developer and open source enthusiast",
  social_links: {
    twitter: "@johndoe",
    github: "johndoe"
  }
}).call
```

### Example 4: Bulk Update with Validation

```ruby
module Product
  class BulkUpdatePriceService < BetterService::UpdateService
    model_class Product
    cache_contexts :products

    schema do
      required(:product_ids).array(:integer)
      required(:price_adjustment).hash do
        required(:type).filled(:string, included_in?: %w[percentage fixed])
        required(:value).filled(:decimal)
      end
    end

    authorize_with do
      user.admin? || user.has_permission?(:bulk_update_prices)
    end

    search_with do
      products = model_class.where(id: params[:product_ids])

      if products.count != params[:product_ids].count
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Some products not found"
        )
      end

      { resources: products }
    end

    process_with do |data|
      products = data[:resources]
      adjustment_type = params[:price_adjustment][:type]
      adjustment_value = params[:price_adjustment][:value]

      updated_count = 0

      products.each do |product|
        old_price = product.price

        new_price = case adjustment_type
        when 'percentage'
          old_price * (1 + adjustment_value / 100.0)
        when 'fixed'
          old_price + adjustment_value
        end

        # Don't allow negative prices
        new_price = [new_price, 0].max

        product.update!(price: new_price.round(2))

        # Log price change
        PriceHistory.create!(
          product: product,
          old_price: old_price,
          new_price: new_price,
          changed_by: user,
          reason: "Bulk update: #{adjustment_type} #{adjustment_value}"
        )

        updated_count += 1
      end

      invalidate_cache_for(user)

      {
        resource: products,
        metadata: {
          updated_count: updated_count,
          adjustment: params[:price_adjustment]
        }
      }
    end

    respond_with do |data|
      count = data[:metadata][:updated_count]
      success_result("Successfully updated #{count} products", data)
    end
  end
end

# Usage
result = Product::BulkUpdatePriceService.new(current_user, params: {
  product_ids: [1, 2, 3, 4, 5],
  price_adjustment: {
    type: 'percentage',
    value: 10  # 10% increase
  }
}).call
```

## Best Practices

### 1. Use Partial Updates

```ruby
# ✅ Good: Optional fields for partial updates
schema do
  required(:id).filled(:integer)
  optional(:name).maybe(:string)
  optional(:price).maybe(:decimal)
end

# Users can update just one field
# { id: 1, name: "New Name" }
# or multiple fields
# { id: 1, name: "New Name", price: 99.99 }
```

### 2. Validate State Transitions

```ruby
process_with do |data|
  resource = data[:resource]

  # Check if transition is allowed
  if resource.published? && params[:status] == 'draft'
    raise BetterService::Errors::Runtime::ValidationError.new(
      "Cannot change published post to draft"
    )
  end

  resource.update!(params.except(:id))
  { resource: resource }
end
```

### 3. Track Changes

```ruby
process_with do |data|
  resource = data[:resource]

  # Get changes before update
  resource.attributes = params.except(:id)

  if resource.changed?
    changes = resource.changes

    resource.save!

    # Log changes
    AuditLog.create!(
      resource: resource,
      changes: changes,
      user: user
    )
  end

  { resource: resource }
end
```

### 4. Handle Association Updates

```ruby
process_with do |data|
  resource = data[:resource]

  # Update base attributes
  resource.update!(params.except(:id, :tag_ids, :category_ids))

  # Update many-to-many associations
  resource.tags = Tag.where(id: params[:tag_ids]) if params[:tag_ids]

  # Update nested attributes
  if params[:settings]
    resource.settings.update!(params[:settings])
  end

  { resource: resource }
end
```

### 5. Invalidate Specific Caches

```ruby
process_with do |data|
  resource = data[:resource]
  price_changed = resource.price_changed?

  resource.update!(params.except(:id))

  # Only invalidate price-related caches if price changed
  if price_changed
    invalidate_cache_for(user, contexts: [:product_prices])
  else
    invalidate_cache_for(user)
  end

  { resource: resource }
end
```

### 6. Send Notifications on Specific Changes

```ruby
process_with do |data|
  resource = data[:resource]

  # Track specific field changes
  status_changed = resource.status != params[:status]

  resource.update!(params.except(:id))

  # Only notify if status changed
  if status_changed
    NotificationService.notify_status_change(resource, user)
  end

  { resource: resource }
end
```

## Testing

### RSpec

```ruby
# spec/services/product/update_service_spec.rb
require 'rails_helper'

RSpec.describe Product::UpdateService do
  let(:user) { create(:user, :admin) }
  let(:product) { create(:product, name: "Original Name", price: 100) }

  describe '#call' do
    it 'updates the product' do
      result = described_class.new(user, params: {
        id: product.id,
        name: "Updated Name"
      }).call

      expect(result[:success]).to be true
      expect(product.reload.name).to eq("Updated Name")
    end

    it 'allows partial updates' do
      result = described_class.new(user, params: {
        id: product.id,
        price: 150
      }).call

      expect(product.reload.price).to eq(150)
      expect(product.name).to eq("Original Name")  # Unchanged
    end

    it 'returns the updated resource' do
      result = described_class.new(user, params: {
        id: product.id,
        name: "New Name"
      }).call

      expect(result[:resource].name).to eq("New Name")
    end

    context 'with invalid params' do
      it 'raises validation error for negative price' do
        expect {
          described_class.new(user, params: {
            id: product.id,
            price: -10
          }).call
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end

    context 'when resource does not exist' do
      it 'raises RecordNotFound error' do
        expect {
          described_class.new(user, params: { id: 99999, name: "Test" }).call
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'authorization' do
      let(:owner) { create(:user) }
      let(:other_user) { create(:user) }
      let(:product) { create(:product, user: owner) }

      it 'allows owner to update' do
        expect {
          described_class.new(owner, params: {
            id: product.id,
            name: "Updated"
          }).call
        }.not_to raise_error
      end

      it 'denies other users from updating' do
        expect {
          described_class.new(other_user, params: {
            id: product.id,
            name: "Updated"
          }).call
        }.to raise_error(BetterService::Errors::Runtime::AuthorizationError)
      end
    end

    context 'cache invalidation' do
      it 'invalidates product caches' do
        expect(Rails.cache).to receive(:delete_matched).with(/products/)

        described_class.new(user, params: {
          id: product.id,
          name: "Updated"
        }).call
      end
    end

    context 'transactions' do
      it 'rolls back on error' do
        allow_any_instance_of(Product).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

        expect {
          described_class.new(user, params: {
            id: product.id,
            name: "Updated"
          }).call rescue nil
        }.not_to change { product.reload.name }
      end
    end
  end
end
```

### Minitest

```ruby
# test/services/product/update_service_test.rb
require 'test_helper'

class Product::UpdateServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @product = products(:laptop)
  end

  test "updates the product" do
    Product::UpdateService.new(@user, params: {
      id: @product.id,
      name: "Updated Name"
    }).call

    assert_equal "Updated Name", @product.reload.name
  end

  test "allows partial updates" do
    original_name = @product.name

    Product::UpdateService.new(@user, params: {
      id: @product.id,
      price: 999.99
    }).call

    assert_equal 999.99, @product.reload.price
    assert_equal original_name, @product.name
  end

  test "raises error for invalid params" do
    assert_raises BetterService::Errors::Runtime::ValidationError do
      Product::UpdateService.new(@user, params: {
        id: @product.id,
        price: -10
      }).call
    end
  end

  test "denies unauthorized updates" do
    other_user = users(:regular)

    assert_raises BetterService::Errors::Runtime::AuthorizationError do
      Product::UpdateService.new(other_user, params: {
        id: @product.id,
        name: "Hacked"
      }).call
    end
  end

  test "rolls back on error" do
    Product.any_instance.stubs(:update!).raises(ActiveRecord::RecordInvalid)

    original_name = @product.name

    Product::UpdateService.new(@user, params: {
      id: @product.id,
      name: "Should Rollback"
    }).call rescue nil

    assert_equal original_name, @product.reload.name
  end
end
```

## Common Patterns

### Pattern 1: Optimistic Locking

```ruby
schema do
  required(:id).filled(:integer)
  required(:lock_version).filled(:integer)
  optional(:name).maybe(:string)
end

process_with do |data|
  resource = data[:resource]

  # Will raise ActiveRecord::StaleObjectError if version doesn't match
  resource.update!(params.except(:id))

  { resource: resource }
end
```

### Pattern 2: Conditional Updates

```ruby
process_with do |data|
  resource = data[:resource]

  # Only update if user is owner or admin
  updateable_params = if user.admin?
    params.except(:id)
  else
    params.except(:id, :status, :featured)  # Regular users can't change status
  end

  resource.update!(updateable_params)

  { resource: resource }
end
```

### Pattern 3: Cascading Updates

```ruby
process_with do |data|
  product = data[:resource]

  product.update!(params.except(:id))

  # Update related records
  if params[:price]
    product.variants.each do |variant|
      variant.update_price_based_on_product!
    end
  end

  { resource: product }
end
```

---

**See also:**
- [Services Structure](01_services_structure.md)
- [CreateService](04_create_service.md)
- [DestroyService](06_destroy_service.md)
- [Service Configurations](08_service_configurations.md)
- [Error Handling](../advanced/error-handling.md)
