# CreateService

## Overview

CreateService is designed for creating new resources. It automatically wraps operations in database transactions and supports cache invalidation, validations, and authorization.

**Characteristics:**
- **Action**: `:created`
- **Transaction**: Enabled (automatic rollback on errors)
- **Return Key**: `resource` (newly created object)
- **Default Schema**: Empty (define your own)
- **Common Use Cases**: Form submissions, API endpoints, resource creation

## Generation

### Basic Generation

```bash
rails g serviceable:create Product
```

This generates:

```ruby
# app/services/product/create_service.rb
module Product
  class CreateService < BetterService::CreateService
    model_class Product

    schema do
      required(:name).filled(:string)
      required(:price).filled(:decimal)
      # Add your required fields
    end

    search_with do
      # Optional: load related data
      {}
    end

    process_with do |data|
      resource = model_class.create!(params)
      { resource: resource }
    end
  end
end
```

### Generation with Options

```bash
# With cache invalidation
rails g serviceable:create Product --cache

# With specific namespace
rails g serviceable:create Admin::Product

# Multiple at once
rails g serviceable:create Product Order Invoice
```

## Schema

### Basic Schema

Define required and optional fields:

```ruby
schema do
  required(:name).filled(:string)
  required(:price).filled(:decimal, gt?: 0)
  optional(:description).maybe(:string)
  optional(:category_id).maybe(:integer)
end
```

### Advanced Validations

```ruby
schema do
  # Required fields
  required(:email).filled(:string, format?: /@/)
  required(:password).filled(:string, min_size?: 8)
  required(:password_confirmation).filled(:string)

  # Conditional validation
  optional(:company_name).maybe(:string)
  optional(:vat_number).maybe(:string)

  # Nested attributes
  optional(:address).hash do
    required(:street).filled(:string)
    required(:city).filled(:string)
    required(:zip).filled(:string)
    optional(:country).filled(:string)
  end

  # Array of values
  optional(:tag_ids).array(:integer)
  optional(:images).array(:hash)

  # Custom validation
  rule(:password, :password_confirmation) do
    if values[:password] != values[:password_confirmation]
      key.failure('passwords do not match')
    end
  end
end
```

### Permitted Attributes

Only allow specific attributes:

```ruby
schema do
  required(:name).filled(:string)
  required(:price).filled(:decimal)

  # Everything else will be rejected
end

process_with do |data|
  # params only contains validated fields
  resource = model_class.create!(params)
  { resource: resource }
end
```

## Available Methods

### search_with

Load related data needed for creation (optional).

**Returns**: Hash with data (empty by default).

```ruby
# Load parent resource
search_with do
  category = Category.find(params[:category_id])
  { category: category }
end

# Load user's data
search_with do
  {
    tenant: user.current_tenant,
    default_settings: user.default_product_settings
  }
end

# Validate uniqueness before creation
search_with do
  if model_class.exists?(email: params[:email])
    raise BetterService::Errors::Runtime::ValidationError.new(
      "Email already exists"
    )
  end
  {}
end
```

### process_with

Creates the resource and performs business logic.

**Input**: Hash from search
**Returns**: Hash with `:resource` key containing created object

```ruby
# Basic creation
process_with do |data|
  resource = model_class.create!(params)
  { resource: resource }
end

# With associations
process_with do |data|
  resource = model_class.create!(params.merge(
    user: user,
    tenant: data[:tenant]
  ))
  { resource: resource }
end

# With related actions
process_with do |data|
  resource = model_class.create!(params)

  # Create related records
  resource.create_default_settings!

  # Send notification
  NotificationMailer.resource_created(resource).deliver_later

  { resource: resource }
end

# With file uploads
process_with do |data|
  resource = model_class.create!(params.except(:images))

  # Attach images
  params[:images]&.each do |image|
    resource.images.attach(image)
  end

  { resource: resource }
end
```

### respond_with

Customizes the success response.

**Input**: Hash from process/transform
**Returns**: Hash with `:success`, `:message`, and data

```ruby
# Custom success message
respond_with do |data|
  success_result("#{data[:resource].name} created successfully", data)
end

# Add extra information
respond_with do |data|
  success_result("Product created", data).merge(
    next_steps: generate_next_steps(data[:resource])
  )
end
```

## Configurations

### Transaction Configuration

Transactions are enabled by default:

```ruby
class Product::CreateService < BetterService::CreateService
  # Automatic transaction wrapping
  # Rolls back on any error

  process_with do |data|
    # Everything here runs in a transaction
    product = Product.create!(params)
    product.create_default_variants!
    { resource: product }
  end
end
```

Disable if needed:

```ruby
class Product::CreateService < BetterService::CreateService
  self._transactional = false

  # No automatic transaction
end
```

### Cache Invalidation

Automatically invalidate caches:

```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product
  cache_contexts :products, :category

  process_with do |data|
    resource = model_class.create!(params)

    # Automatically invalidates :products and :category caches
    invalidate_cache_for(user)

    { resource: resource }
  end
end
```

### Authorization

Ensure user can create resources:

```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product

  authorize_with do
    user.admin? || user.has_permission?(:create_products)
  end

  process_with do |data|
    resource = model_class.create!(params.merge(user: user))
    { resource: resource }
  end
end
```

### Presenter Configuration

Format the created resource:

```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product
  presenter ProductPresenter

  process_with do |data|
    resource = model_class.create!(params)
    { resource: resource }
  end
end
```

## Complete Examples

### Example 1: Basic Product Creation

```ruby
module Product
  class CreateService < BetterService::CreateService
    model_class Product
    cache_contexts :products

    schema do
      required(:name).filled(:string)
      required(:price).filled(:decimal, gt?: 0)
      required(:category_id).filled(:integer)
      optional(:description).maybe(:string)
    end

    authorize_with do
      user.admin? || user.seller?
    end

    search_with do
      category = Category.find(params[:category_id])
      { category: category }
    end

    process_with do |data|
      resource = model_class.create!(
        params.merge(user: user)
      )

      invalidate_cache_for(user)

      { resource: resource }
    end
  end
end

# Usage
result = Product::CreateService.new(current_user, params: {
  name: "Gaming Laptop",
  price: 1299.99,
  category_id: 5,
  description: "High-performance laptop"
}).call

product = result[:resource]
# => #<Product id: 123, name: "Gaming Laptop", ...>
```

### Example 2: User Registration

```ruby
module User
  class RegisterService < BetterService::CreateService
    model_class User
    cache_contexts :users

    schema do
      required(:email).filled(:string, format?: /@/)
      required(:password).filled(:string, min_size?: 8)
      required(:password_confirmation).filled(:string)
      required(:first_name).filled(:string)
      required(:last_name).filled(:string)

      optional(:company_name).maybe(:string)
      optional(:terms_accepted).filled(:bool)

      rule(:password, :password_confirmation) do
        if values[:password] != values[:password_confirmation]
          key.failure('passwords must match')
        end
      end

      rule(:terms_accepted) do
        if values[:terms_accepted] != true
          key.failure('must accept terms and conditions')
        end
      end
    end

    search_with do
      # Check email uniqueness
      if User.exists?(email: params[:email].downcase)
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Email already registered"
        )
      end

      {}
    end

    process_with do |data|
      # Create user
      user = model_class.create!(
        email: params[:email].downcase,
        password: params[:password],
        first_name: params[:first_name],
        last_name: params[:last_name],
        company_name: params[:company_name]
      )

      # Generate verification token
      user.generate_verification_token!

      # Send welcome email
      UserMailer.welcome_email(user).deliver_later

      # Send verification email
      UserMailer.verification_email(user).deliver_later

      invalidate_cache_for(user)

      { resource: user }
    end

    respond_with do |data|
      success_result("Registration successful. Please check your email.", data)
    end
  end
end

# Usage
result = User::RegisterService.new(nil, params: {
  email: "user@example.com",
  password: "SecurePass123",
  password_confirmation: "SecurePass123",
  first_name: "John",
  last_name: "Doe",
  terms_accepted: true
}).call
```

### Example 3: Order Creation with Items

```ruby
module Order
  class CreateService < BetterService::CreateService
    model_class Order
    cache_contexts :orders, :user_orders

    schema do
      required(:items).array(:hash) do
        required(:product_id).filled(:integer)
        required(:quantity).filled(:integer, gt?: 0)
      end

      required(:shipping_address).hash do
        required(:street).filled(:string)
        required(:city).filled(:string)
        required(:zip).filled(:string)
        required(:country).filled(:string)
      end

      optional(:coupon_code).maybe(:string)
    end

    authorize_with do
      user.present? && user.active?
    end

    search_with do
      # Load products
      product_ids = params[:items].map { |item| item[:product_id] }
      products = Product.where(id: product_ids).index_by(&:id)

      # Validate all products exist
      if products.size != product_ids.uniq.size
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Some products not found"
        )
      end

      # Validate stock
      params[:items].each do |item|
        product = products[item[:product_id]]
        if product.stock < item[:quantity]
          raise BetterService::Errors::Runtime::ValidationError.new(
            "Insufficient stock for #{product.name}"
          )
        end
      end

      # Load coupon if provided
      coupon = params[:coupon_code] ?
        Coupon.find_by(code: params[:coupon_code]) :
        nil

      { products: products, coupon: coupon }
    end

    process_with do |data|
      products = data[:products]
      coupon = data[:coupon]

      # Calculate totals
      subtotal = params[:items].sum do |item|
        product = products[item[:product_id]]
        product.price * item[:quantity]
      end

      discount = coupon ? calculate_discount(subtotal, coupon) : 0
      total = subtotal - discount

      # Create order
      order = model_class.create!(
        user: user,
        subtotal: subtotal,
        discount: discount,
        total: total,
        status: 'pending',
        shipping_address: params[:shipping_address]
      )

      # Create order items
      params[:items].each do |item|
        product = products[item[:product_id]]
        order.items.create!(
          product: product,
          quantity: item[:quantity],
          unit_price: product.price,
          total_price: product.price * item[:quantity]
        )

        # Decrement stock
        product.decrement!(:stock, item[:quantity])
      end

      # Mark coupon as used
      coupon&.increment!(:usage_count)

      # Send confirmation email
      OrderMailer.confirmation(order).deliver_later

      invalidate_cache_for(user)

      { resource: order }
    end

    private

    def calculate_discount(subtotal, coupon)
      case coupon.type
      when 'percentage'
        subtotal * (coupon.value / 100.0)
      when 'fixed'
        [coupon.value, subtotal].min
      else
        0
      end
    end
  end
end

# Usage
result = Order::CreateService.new(current_user, params: {
  items: [
    { product_id: 1, quantity: 2 },
    { product_id: 5, quantity: 1 }
  ],
  shipping_address: {
    street: "123 Main St",
    city: "New York",
    zip: "10001",
    country: "USA"
  },
  coupon_code: "SAVE20"
}).call
```

### Example 4: Blog Post with Tags

```ruby
module Post
  class CreateService < BetterService::CreateService
    model_class Post
    cache_contexts :posts, :user_posts
    presenter PostPresenter

    schema do
      required(:title).filled(:string, min_size?: 5)
      required(:content).filled(:string, min_size?: 100)
      required(:category_id).filled(:integer)

      optional(:tag_names).array(:string)
      optional(:featured_image).filled(:hash)
      optional(:publish_immediately).filled(:bool)
    end

    authorize_with do
      user.author? || user.admin?
    end

    search_with do
      category = Category.find(params[:category_id])
      { category: category }
    end

    process_with do |data|
      # Create post
      post = model_class.create!(
        title: params[:title],
        content: params[:content],
        category: data[:category],
        user: user,
        status: params[:publish_immediately] ? 'published' : 'draft',
        published_at: params[:publish_immediately] ? Time.current : nil
      )

      # Handle tags
      if params[:tag_names].present?
        params[:tag_names].each do |tag_name|
          tag = Tag.find_or_create_by!(name: tag_name.downcase)
          post.tags << tag
        end
      end

      # Attach featured image
      if params[:featured_image]
        post.featured_image.attach(params[:featured_image])
      end

      # Generate slug
      post.update!(slug: generate_slug(post.title, post.id))

      # Send notification if published
      if post.published?
        NotificationService.notify_followers(user, post)
      end

      invalidate_cache_for(user)

      { resource: post }
    end

    respond_with do |data|
      message = data[:resource].published? ?
        "Post published successfully" :
        "Post saved as draft"

      success_result(message, data)
    end

    private

    def generate_slug(title, id)
      base = title.parameterize
      "#{base}-#{id}"
    end
  end
end

# Usage
result = Post::CreateService.new(current_user, params: {
  title: "Getting Started with Rails",
  content: "Long content here...",
  category_id: 3,
  tag_names: ["rails", "tutorial", "ruby"],
  publish_immediately: true
}).call
```

## Best Practices

### 1. Always Use Transactions

CreateService enables transactions by default - keep it that way:

```ruby
# ✅ Good: Transaction wraps everything
process_with do |data|
  order = Order.create!(params)
  order.items.create!(item_params)
  order.charge_payment!
  { resource: order }
end
# If any step fails, everything rolls back
```

### 2. Validate Business Rules in Search Phase

```ruby
search_with do
  # Check stock availability
  if product.stock < params[:quantity]
    raise BetterService::Errors::Runtime::ValidationError.new(
      "Insufficient stock"
    )
  end

  # Check duplicate orders
  if user.orders.pending.exists?(product_id: params[:product_id])
    raise BetterService::Errors::Runtime::ValidationError.new(
      "You already have a pending order for this product"
    )
  end

  { product: product }
end
```

### 3. Use Strong Parameter Validation

```ruby
# ✅ Good: Explicit schema
schema do
  required(:name).filled(:string)
  required(:price).filled(:decimal, gt?: 0)
  optional(:description).maybe(:string)
end

# Only validated params are accessible
process_with do |data|
  model_class.create!(params)  # Only name, price, description
end
```

### 4. Invalidate Related Caches

```ruby
class Product::CreateService < BetterService::CreateService
  cache_contexts :products, :category_products, :search

  process_with do |data|
    resource = model_class.create!(params)

    # Invalidates all related caches
    invalidate_cache_for(user)

    { resource: resource }
  end
end
```

### 5. Handle File Uploads Properly

```ruby
process_with do |data|
  # Create record first
  resource = model_class.create!(params.except(:images, :documents))

  # Then attach files (outside transaction if possible)
  params[:images]&.each { |img| resource.images.attach(img) }
  params[:documents]&.each { |doc| resource.documents.attach(doc) }

  { resource: resource }
end
```

### 6. Send Async Notifications

```ruby
process_with do |data|
  resource = model_class.create!(params)

  # Use deliver_later for async processing
  NotificationMailer.resource_created(resource).deliver_later
  SlackNotifier.notify_team(resource).deliver_later

  { resource: resource }
end
```

## Testing

### RSpec

```ruby
# spec/services/product/create_service_spec.rb
require 'rails_helper'

RSpec.describe Product::CreateService do
  let(:user) { create(:user, :admin) }
  let(:category) { create(:category) }

  let(:valid_params) do
    {
      name: "Gaming Laptop",
      price: 1299.99,
      category_id: category.id,
      description: "High-performance laptop"
    }
  end

  describe '#call' do
    it 'creates a product' do
      expect {
        described_class.new(user, params: valid_params).call
      }.to change(Product, :count).by(1)
    end

    it 'returns the created product' do
      result = described_class.new(user, params: valid_params).call

      expect(result[:success]).to be true
      expect(result[:resource]).to be_a(Product)
      expect(result[:resource].name).to eq("Gaming Laptop")
    end

    it 'associates product with user' do
      result = described_class.new(user, params: valid_params).call

      expect(result[:resource].user).to eq(user)
    end

    context 'with invalid params' do
      it 'raises validation error for missing name' do
        expect {
          described_class.new(user, params: valid_params.except(:name)).call
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end

      it 'raises validation error for negative price' do
        expect {
          described_class.new(user, params: valid_params.merge(price: -10)).call
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end

    context 'authorization' do
      let(:regular_user) { create(:user) }

      it 'allows admin to create products' do
        expect {
          described_class.new(user, params: valid_params).call
        }.not_to raise_error
      end

      it 'denies regular user from creating products' do
        expect {
          described_class.new(regular_user, params: valid_params).call
        }.to raise_error(BetterService::Errors::Runtime::AuthorizationError)
      end
    end

    context 'cache invalidation' do
      it 'invalidates product caches' do
        expect(Rails.cache).to receive(:delete_matched).with(/products/)

        described_class.new(user, params: valid_params).call
      end
    end

    context 'transactions' do
      it 'rolls back on error' do
        allow_any_instance_of(Product).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)

        expect {
          described_class.new(user, params: valid_params).call rescue nil
        }.not_to change(Product, :count)
      end
    end
  end
end
```

### Minitest

```ruby
# test/services/product/create_service_test.rb
require 'test_helper'

class Product::CreateServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @category = categories(:electronics)

    @valid_params = {
      name: "Gaming Laptop",
      price: 1299.99,
      category_id: @category.id
    }
  end

  test "creates a product" do
    assert_difference 'Product.count', 1 do
      Product::CreateService.new(@user, params: @valid_params).call
    end
  end

  test "returns created product" do
    result = Product::CreateService.new(@user, params: @valid_params).call

    assert result[:success]
    assert_instance_of Product, result[:resource]
    assert_equal "Gaming Laptop", result[:resource].name
  end

  test "raises validation error for invalid params" do
    assert_raises BetterService::Errors::Runtime::ValidationError do
      Product::CreateService.new(@user, params: {}).call
    end
  end

  test "denies unauthorized users" do
    regular_user = users(:regular)

    assert_raises BetterService::Errors::Runtime::AuthorizationError do
      Product::CreateService.new(regular_user, params: @valid_params).call
    end
  end

  test "rolls back on error" do
    Product.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid)

    assert_no_difference 'Product.count' do
      Product::CreateService.new(@user, params: @valid_params).call rescue nil
    end
  end
end
```

---

**See also:**
- [Services Structure](01_services_structure.md)
- [UpdateService](05_update_service.md)
- [DestroyService](06_destroy_service.md)
- [Service Configurations](08_service_configurations.md)
- [Error Handling](../advanced/error-handling.md)
