# Testing Guide

Comprehensive guide for testing BetterService services with Minitest (or RSpec). Learn patterns for testing validation, authorization, success paths, error scenarios, and workflows.

## Table of Contents

- [Overview](#overview)
- [Test Setup](#test-setup)
- [Testing Validation](#testing-validation)
- [Testing Authorization](#testing-authorization)
- [Testing Success Scenarios](#testing-success-scenarios)
- [Testing Error Scenarios](#testing-error-scenarios)
- [Testing Workflows](#testing-workflows)
- [Testing with Caching](#testing-with-caching)
- [Best Practices](#best-practices)

---

## Overview

### Testing Philosophy

BetterService uses a **Pure Exception Pattern**, which means:
- ✅ Services raise exceptions on errors
- ✅ Use `assert_raises` for error cases
- ❌ No `success`/`failure` flags to check

### Test Framework

Examples use **Minitest** (Rails default), but patterns work with RSpec too.

---

## Test Setup

### Basic Test Structure

```ruby
require "test_helper"

class Product::CreateServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)  # Fixture or factory
    @valid_params = {
      name: "Test Product",
      price: 99.99
    }
  end

  test "creates product with valid params" do
    result = Product::CreateService.new(@user, params: @valid_params).call

    assert result[:success]
    assert_instance_of Product, result[:resource]
    assert_equal "Test Product", result[:resource].name
  end
end
```

---

### Fixtures

```yaml
# test/fixtures/users.yml
admin:
  email: admin@example.com
  role: admin

regular:
  email: user@example.com
  role: user
```

---

### Factories (FactoryBot)

```ruby
# test/factories/users.rb
FactoryBot.define do
  factory :user do
    email { "user@example.com" }
    role { "user" }

    trait :admin do
      role { "admin" }
    end
  end
end

# In test
@user = create(:user, :admin)
```

---

## Testing Validation

### Test Required Fields

```ruby
test "validates required name" do
  params = { price: 99.99 }  # Missing name

  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(@user, params: params)
  end

  assert_equal :validation_failed, error.code
  assert error.context[:validation_errors].key?(:name)
  assert_includes error.context[:validation_errors][:name], "must be filled"
end
```

---

### Test Type Validation

```ruby
test "validates price is decimal" do
  params = { name: "Product", price: "not_a_number" }

  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(@user, params: params)
  end

  assert error.context[:validation_errors].key?(:price)
end
```

---

### Test Predicate Validation

```ruby
test "validates price is greater than zero" do
  params = { name: "Product", price: -10 }

  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(@user, params: params)
  end

  assert_includes error.context[:validation_errors][:price], "must be greater than 0"
end
```

---

### Test Optional Fields

```ruby
test "allows optional description" do
  params = { name: "Product", price: 99.99 }  # No description

  result = Product::CreateService.new(@user, params: params).call

  assert result[:success]
  assert_nil result[:resource].description
end

test "accepts description when provided" do
  params = { name: "Product", price: 99.99, description: "Great product" }

  result = Product::CreateService.new(@user, params: params).call

  assert result[:success]
  assert_equal "Great product", result[:resource].description
end
```

---

### Test Nested Validation

```ruby
test "validates nested address" do
  params = {
    name: "Product",
    price: 99.99,
    address: {
      street: "",  # Invalid
      city: "New York"
    }
  }

  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(@user, params: params)
  end

  assert error.context[:validation_errors].key?(:address)
end
```

---

## Testing Authorization

### Test Authorized User

```ruby
test "allows admin to update product" do
  admin = users(:admin)
  product = products(:laptop)

  result = Product::UpdateService.new(admin, params: {
    id: product.id,
    name: "Updated Name"
  }).call

  assert result[:success]
  assert_equal "Updated Name", result[:resource].name
end
```

---

### Test Unauthorized User

```ruby
test "prevents non-owner from updating product" do
  other_user = users(:other)
  product = products(:laptop)  # Owned by @user

  error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
    Product::UpdateService.new(other_user, params: {
      id: product.id,
      name: "Updated"
    }).call
  end

  assert_equal :unauthorized, error.code
  assert_equal "Product::UpdateService", error.context[:service]
end
```

---

### Test Role-Based Authorization

```ruby
test "allows admin to delete any product" do
  admin = users(:admin)
  product = products(:laptop)

  result = Product::DestroyService.new(admin, params: { id: product.id }).call

  assert result[:success]
  assert_nil Product.find_by(id: product.id)
end

test "prevents regular user from deleting" do
  regular = users(:regular)
  product = products(:laptop)

  error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
    Product::DestroyService.new(regular, params: { id: product.id }).call
  end

  assert_equal :unauthorized, error.code
end
```

---

## Testing Success Scenarios

### Test Create Service

```ruby
test "creates product with valid params" do
  params = { name: "New Product", price: 149.99 }

  assert_difference "Product.count", 1 do
    result = Product::CreateService.new(@user, params: params).call

    assert result[:success]
    assert_equal :created, result[:metadata][:action]
    assert_equal "New Product", result[:resource].name
    assert_equal 149.99, result[:resource].price
  end
end
```

---

### Test Update Service

```ruby
test "updates product attributes" do
  product = products(:laptop)
  params = { id: product.id, price: 1299.99 }

  result = Product::UpdateService.new(@user, params: params).call

  assert result[:success]
  assert_equal :updated, result[:metadata][:action]
  assert_equal 1299.99, result[:resource].price
end
```

---

### Test Destroy Service

```ruby
test "destroys product" do
  product = products(:laptop)

  assert_difference "Product.count", -1 do
    result = Product::DestroyService.new(@user, params: { id: product.id }).call

    assert result[:success]
    assert_equal :destroyed, result[:metadata][:action]
  end
end
```

---

### Test Index Service

```ruby
test "lists products with filtering" do
  products(:laptop)  # Category: electronics
  products(:book)    # Category: books

  result = Product::IndexService.new(@user, params: { category: "electronics" }).call

  assert result[:success]
  assert_equal 1, result[:items].count
  assert_equal "electronics", result[:items].first.category
end
```

---

### Test Show Service

```ruby
test "shows product details" do
  product = products(:laptop)

  result = Product::ShowService.new(@user, params: { id: product.id }).call

  assert result[:success]
  assert_equal :show, result[:metadata][:action]
  assert_equal product.id, result[:resource].id
end
```

---

## Testing Error Scenarios

### Test Validation Errors

```ruby
test "raises validation error for invalid params" do
  params = { name: "", price: -10 }

  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(@user, params: params)
  end

  assert_equal :validation_failed, error.code
  assert error.context[:validation_errors].key?(:name)
  assert error.context[:validation_errors].key?(:price)
end
```

---

### Test Database Errors

```ruby
test "raises database error for unique constraint violation" do
  Product.create!(name: "Unique", sku: "SKU123")

  error = assert_raises(BetterService::Errors::Runtime::DatabaseError) do
    Product::CreateService.new(@user, params: {
      name: "Another",
      sku: "SKU123"  # Duplicate SKU
    }).call
  end

  assert_equal :database_error, error.code
  assert_instance_of ActiveRecord::RecordInvalid, error.original_error
end
```

---

### Test Resource Not Found

```ruby
test "raises not found error for missing product" do
  error = assert_raises(BetterService::Errors::Runtime::ResourceNotFoundError) do
    Product::ShowService.new(@user, params: { id: 99999 }).call
  end

  assert_equal :resource_not_found, error.code
  assert_instance_of ActiveRecord::RecordNotFound, error.original_error
end
```

---

### Test Transaction Rollback

```ruby
test "rolls back transaction on error" do
  # Stub external service to fail
  ExternalService.stub :call, -> { raise "External error" } do
    assert_no_difference "Product.count" do
      assert_raises(BetterService::Errors::Runtime::ExecutionError) do
        Product::CreateService.new(@user, params: {
          name: "Product",
          price: 99.99
        }).call
      end
    end
  end
end
```

---

## Testing Workflows

### Test Successful Workflow

```ruby
test "completes checkout workflow" do
  cart = carts(:user_cart)

  result = Order::CheckoutWorkflow.new(@user, params: {
    cart_id: cart.id,
    payment_method: "card_123"
  }).call

  assert result[:success]
  assert result[:context].order.present?
  assert result[:context].charge_payment.present?
  assert_equal [:create_order, :charge_payment, :send_email], result[:metadata][:steps_executed]
end
```

---

### Test Workflow Rollback

```ruby
test "rolls back workflow on payment failure" do
  cart = carts(:user_cart)

  # Stub payment service to fail
  Payment::ChargeService.stub :call, -> { raise "Payment declined" } do
    result = Order::CheckoutWorkflow.new(@user, params: {
      cart_id: cart.id,
      payment_method: "invalid"
    }).call

    assert result[:failure?]
    assert_equal :charge_payment, result[:metadata][:failed_step]
    assert_nil Order.last  # Order rolled back
  end
end
```

---

### Test Conditional Steps

```ruby
test "skips optional steps when condition not met" do
  cart = carts(:small_cart)  # Total < $100

  result = Order::CheckoutWorkflow.new(@user, params: {
    cart_id: cart.id
  }).call

  assert result[:success]
  assert_includes result[:metadata][:steps_skipped], :send_premium_email
end
```

---

### Test Workflow Context

```ruby
test "passes data between steps" do
  result = Order::CheckoutWorkflow.new(@user, params: valid_params).call

  # Access data from different steps
  order = result[:context].create_order
  charge = result[:context].charge_payment

  assert_equal order.total, charge.amount
end
```

---

## Testing with Caching

### Test Cache Hit

```ruby
test "returns cached result on second call" do
  params = { category: "electronics" }

  # First call - cache miss
  result1 = Product::IndexService.new(@user, params: params).call
  assert result1[:success]

  # Create new product
  Product.create!(name: "New Product", category: "electronics")

  # Second call - cache hit (won't see new product)
  result2 = Product::IndexService.new(@user, params: params).call
  assert_equal result1[:items].count, result2[:items].count
end
```

---

### Test Cache Invalidation

```ruby
test "invalidates cache after create" do
  params = { category: "electronics" }

  # First call - cache miss
  result1 = Product::IndexService.new(@user, params: params).call
  count1 = result1[:items].count

  # Create product and invalidate cache
  Product::CreateService.new(@user, params: {
    name: "New Product",
    category: "electronics",
    price: 99.99
  }).call

  # Second call - cache miss (sees new product)
  result2 = Product::IndexService.new(@user, params: params).call
  assert_equal count1 + 1, result2[:items].count
end
```

---

### Clear Cache Between Tests

```ruby
class Product::IndexServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    Rails.cache.clear  # Clear cache before each test
  end

  # Tests...
end
```

---

## Best Practices

### 1. Test Both Success and Error Paths

```ruby
# ✅ Good - test both paths
test "creates product with valid params" do
  # Test success
end

test "raises error for invalid params" do
  # Test error
end

# ❌ Bad - only test success
test "creates product" do
  # Only success path
end
```

---

### 2. Use Descriptive Test Names

```ruby
# ✅ Good - descriptive
test "prevents non-admin from deleting products"
test "validates price is greater than zero"
test "rolls back transaction on payment failure"

# ❌ Bad - vague
test "it works"
test "delete"
test "error"
```

---

### 3. Test One Thing Per Test

```ruby
# ✅ Good - focused test
test "validates required name" do
  # Only test name validation
end

test "validates required price" do
  # Only test price validation
end

# ❌ Bad - tests multiple things
test "validates all fields" do
  # Tests name, price, description, etc.
end
```

---

### 4. Use Setup for Common Data

```ruby
# ✅ Good - DRY
class Product::CreateServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @valid_params = { name: "Product", price: 99.99 }
  end

  test "creates product" do
    result = Product::CreateService.new(@user, params: @valid_params).call
    # ...
  end
end

# ❌ Bad - repetitive
test "creates product" do
  user = users(:admin)
  params = { name: "Product", price: 99.99 }
  # ...
end

test "updates product" do
  user = users(:admin)  # Duplicated
  params = { name: "Product", price: 99.99 }  # Duplicated
  # ...
end
```

---

### 5. Test Error Context

```ruby
# ✅ Good - verify error details
test "raises authorization error" do
  error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
    service.call
  end

  assert_equal :unauthorized, error.code
  assert_equal "ProductService", error.context[:service]
  assert error.context[:user].present?
end

# ❌ Bad - only check that error raised
test "raises authorization error" do
  assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
    service.call
  end
end
```

---

### 6. Test Metadata

```ruby
# ✅ Good - verify metadata
test "includes action metadata" do
  result = Product::CreateService.new(@user, params: @valid_params).call

  assert_equal :created, result[:metadata][:action]
end
```

---

### 7. Use Factories for Complex Objects

```ruby
# ✅ Good - factories for complex setup
test "processes order with multiple items" do
  order = create(:order, :with_items, item_count: 5)
  result = Order::ProcessService.new(@user, params: { id: order.id }).call
  # ...
end
```

---

## RSpec Examples

### Basic RSpec Structure

```ruby
require "rails_helper"

RSpec.describe Product::CreateService do
  let(:user) { create(:user, :admin) }
  let(:valid_params) { { name: "Product", price: 99.99 } }

  describe "#call" do
    context "with valid params" do
      it "creates a product" do
        result = described_class.new(user, params: valid_params).call

        expect(result[:success]).to be true
        expect(result[:resource]).to be_a(Product)
        expect(result[:resource].name).to eq("Product")
      end
    end

    context "with invalid params" do
      let(:invalid_params) { { name: "", price: -10 } }

      it "raises validation error" do
        expect {
          described_class.new(user, params: invalid_params)
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end
  end
end
```

---

## Testing Checklist

For each service, test:

- [ ] **Validation**
  - [ ] Required fields
  - [ ] Optional fields
  - [ ] Type validation
  - [ ] Predicate validation
  - [ ] Nested validation

- [ ] **Authorization**
  - [ ] Authorized users
  - [ ] Unauthorized users
  - [ ] Different roles

- [ ] **Success Path**
  - [ ] Happy path execution
  - [ ] Return value structure
  - [ ] Metadata presence

- [ ] **Error Scenarios**
  - [ ] Validation errors
  - [ ] Authorization errors
  - [ ] Database errors
  - [ ] Not found errors
  - [ ] Transaction rollback

- [ ] **Side Effects** (if applicable)
  - [ ] Records created/updated/deleted
  - [ ] Cache invalidated
  - [ ] External APIs called
  - [ ] Emails sent

---

## Next Steps

- **[Getting Started](start/getting-started.md)** - Build your first service
- **[Error Handling](advanced/error-handling.md)** - Handle errors in tests
- **[Service Types](services/01_services_structure.md)** - Learn service patterns

---

**See Also:**
- [Configuration Guide](start/configuration.md)
- [Concerns Reference](concerns-reference.md)
- [Workflows](workflows/01_workflows_introduction.md)
