# Testing

Learn to test BetterService services and workflows.

---

## Testing Philosophy

### What to Test

Focus on these key areas.

```ruby
# 1. Validation - Schema rejects invalid params
# 2. Authorization - Permissions are enforced
# 3. Success path - Service works correctly
# 4. Error handling - Errors are raised/returned appropriately
# 5. Side effects - Database changes, external calls
```

--------------------------------

## Basic Test Structure

### Service Test Template

Standard structure for service tests.

```ruby
require "test_helper"

class Product::CreateServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:seller)
    @admin = users(:admin)
    @valid_params = { name: "Widget", price: 99.99 }
  end

  test "creates product with valid params" do
    result = Product::CreateService.new(@user, params: @valid_params).call

    assert result.success?
    assert_instance_of Product, result.resource
    assert_equal "Widget", result.resource.name
    assert_equal :created, result.meta[:action]
  end

  test "returns failure for unauthorized user" do
    non_seller = users(:regular)
    result = Product::CreateService.new(non_seller, params: @valid_params).call

    refute result.success?
    assert_equal :unauthorized, result.meta[:error_code]
  end

  test "raises ValidationError for invalid params" do
    error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
      Product::CreateService.new(@user, params: { name: "" })
    end

    assert_equal :validation_failed, error.code
    assert error.context[:validation_errors].key?(:name)
  end
end
```

--------------------------------

## Testing Validation

### Test Required Fields

Verify required fields are validated.

```ruby
test "validates name is required" do
  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(@user, params: { price: 99.99 })
  end

  assert error.context[:validation_errors].key?(:name)
  assert_includes error.context[:validation_errors][:name], "is missing"
end

test "validates price is required" do
  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(@user, params: { name: "Widget" })
  end

  assert error.context[:validation_errors].key?(:price)
end
```

--------------------------------

### Test Value Constraints

Verify constraints are enforced.

```ruby
test "validates price must be positive" do
  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(@user, params: { name: "Widget", price: -10 })
  end

  assert error.context[:validation_errors].key?(:price)
end

test "validates name minimum length" do
  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(@user, params: { name: "X", price: 99.99 })
  end

  assert error.context[:validation_errors].key?(:name)
end
```

--------------------------------

## Testing Authorization

### Test Admin Access

Verify admin bypass works.

```ruby
test "allows admin to update any product" do
  admin = users(:admin)
  product = products(:other_user_product)

  result = Product::UpdateService.new(
    admin,
    params: { id: product.id, name: "New Name" }
  ).call

  assert result.success?
  assert_equal "New Name", result.resource.name
end
```

--------------------------------

### Test Owner Access

Verify owners can access their resources.

```ruby
test "allows owner to update own product" do
  owner = users(:seller)
  product = products(:seller_product)

  result = Product::UpdateService.new(
    owner,
    params: { id: product.id, name: "New Name" }
  ).call

  assert result.success?
end

test "denies non-owner from updating product" do
  other_user = users(:other_seller)
  product = products(:seller_product)

  result = Product::UpdateService.new(
    other_user,
    params: { id: product.id, name: "New Name" }
  ).call

  refute result.success?
  assert_equal :unauthorized, result.meta[:error_code]
end
```

--------------------------------

## Testing Success Path

### Test Create Service

Verify create works correctly.

```ruby
test "creates product with all attributes" do
  result = Product::CreateService.new(
    @user,
    params: {
      name: "Widget",
      price: 99.99,
      description: "A great widget"
    }
  ).call

  assert result.success?
  assert_equal "Widget", result.resource.name
  assert_equal 99.99, result.resource.price
  assert_equal "A great widget", result.resource.description
  assert_equal @user.id, result.resource.user_id
end

test "creates product in database" do
  assert_difference "Product.count", 1 do
    Product::CreateService.new(@user, params: @valid_params).call
  end
end
```

--------------------------------

### Test Update Service

Verify update works correctly.

```ruby
test "updates product attributes" do
  product = products(:seller_product)

  result = Product::UpdateService.new(
    @user,
    params: { id: product.id, name: "New Name", price: 149.99 }
  ).call

  assert result.success?
  assert_equal "New Name", result.resource.name
  assert_equal 149.99, result.resource.price
end

test "only updates provided attributes" do
  product = products(:seller_product)
  original_description = product.description

  result = Product::UpdateService.new(
    @user,
    params: { id: product.id, name: "New Name" }
  ).call

  assert result.success?
  assert_equal original_description, result.resource.description
end
```

--------------------------------

### Test Destroy Service

Verify destroy works correctly.

```ruby
test "destroys product" do
  product = products(:seller_product)

  assert_difference "Product.count", -1 do
    Product::DestroyService.new(@user, params: { id: product.id }).call
  end
end

test "returns destroyed product in result" do
  product = products(:seller_product)

  result = Product::DestroyService.new(@user, params: { id: product.id }).call

  assert result.success?
  assert_equal product.id, result.resource.id
end
```

--------------------------------

## Testing Errors

### Test ResourceNotFoundError

Verify not found is raised.

```ruby
test "raises ResourceNotFoundError for non-existent product" do
  error = assert_raises(BetterService::Errors::Runtime::ResourceNotFoundError) do
    Product::ShowService.new(@user, params: { id: 999999 }).call
  end

  assert_equal :resource_not_found, error.code
  assert_equal 999999, error.context[:id]
end
```

--------------------------------

### Test ExecutionError

Verify business logic errors.

```ruby
test "raises error when publishing already published product" do
  product = products(:published_product)

  error = assert_raises(BetterService::Errors::Runtime::ExecutionError) do
    Product::PublishService.new(@user, params: { id: product.id }).call
  end

  assert_match /already published/, error.message
end
```

--------------------------------

## Testing Destructuring

### Test Destructuring Support

Verify destructuring works.

```ruby
test "supports destructuring" do
  product, meta = Product::CreateService.new(@user, params: @valid_params).call

  assert_instance_of Product, product
  assert_equal :created, meta[:action]
  assert meta[:success]
end
```

--------------------------------

## Testing Workflows

### Test Workflow Success

Verify workflow completes successfully.

```ruby
test "checkout workflow completes successfully" do
  cart = carts(:valid_cart)

  result = Order::CheckoutWorkflow.new(
    @user,
    params: { cart_id: cart.id }
  ).call

  assert result[:success]
  assert_includes result[:metadata][:steps_executed], :validate_cart
  assert_includes result[:metadata][:steps_executed], :create_order
end
```

--------------------------------

### Test Workflow Branching

Verify correct branch is taken.

```ruby
test "takes credit card path for credit card payment" do
  cart = carts(:credit_card_cart)

  result = Order::CheckoutWorkflow.new(
    @user,
    params: { cart_id: cart.id }
  ).call

  assert result[:success]
  assert_includes result[:metadata][:steps_executed], :charge_card
  refute_includes result[:metadata][:steps_executed], :charge_paypal
end

test "takes paypal path for paypal payment" do
  cart = carts(:paypal_cart)

  result = Order::CheckoutWorkflow.new(
    @user,
    params: { cart_id: cart.id }
  ).call

  assert result[:success]
  assert_includes result[:metadata][:steps_executed], :charge_paypal
  refute_includes result[:metadata][:steps_executed], :charge_card
end
```

--------------------------------

### Test Workflow Rollback

Verify rollback on failure.

```ruby
test "rolls back on payment failure" do
  cart = carts(:valid_cart)

  # Mock payment to fail
  Payment::ChargeService.any_instance.stubs(:call).raises(
    BetterService::Errors::Runtime::ExecutionError.new("Payment failed")
  )

  assert_no_difference "Order.count" do
    assert_raises(BetterService::Errors::Workflowable::Runtime::StepExecutionError) do
      Order::CheckoutWorkflow.new(@user, params: { cart_id: cart.id }).call
    end
  end
end
```

--------------------------------

## Test Helpers

### Custom Assertions

Create helper methods for common assertions.

```ruby
# test/test_helper.rb
class ActiveSupport::TestCase
  def assert_service_success(result)
    assert result.success?, "Expected success but got: #{result.message}"
  end

  def assert_service_failure(result, error_code: nil)
    refute result.success?, "Expected failure but got success"
    if error_code
      assert_equal error_code, result.meta[:error_code]
    end
  end

  def assert_validation_error(error, field)
    assert_equal :validation_failed, error.code
    assert error.context[:validation_errors].key?(field),
           "Expected validation error for #{field}"
  end
end
```

--------------------------------

### Using Helper Methods

Use helpers in tests.

```ruby
test "creates product successfully" do
  result = Product::CreateService.new(@user, params: @valid_params).call
  assert_service_success(result)
end

test "fails for unauthorized user" do
  result = Product::UpdateService.new(non_owner, params: params).call
  assert_service_failure(result, error_code: :unauthorized)
end

test "validates name is required" do
  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(@user, params: { price: 99.99 })
  end
  assert_validation_error(error, :name)
end
```

--------------------------------

## Testing Side Effects

### Test Database Changes

Verify database state changes.

```ruby
test "creates associated records" do
  assert_difference ["Order.count", "OrderItem.count"], 1 do
    Order::CreateService.new(@user, params: order_params).call
  end
end

test "updates inventory on order creation" do
  product = products(:widget)
  initial_stock = product.stock

  Order::CreateService.new(@user, params: { product_id: product.id, quantity: 2 }).call

  assert_equal initial_stock - 2, product.reload.stock
end
```

--------------------------------

### Test External Calls (Mocking)

Mock external services.

```ruby
test "sends email on successful order" do
  ActionMailer::Base.deliveries.clear

  Order::CreateService.new(@user, params: order_params).call

  assert_equal 1, ActionMailer::Base.deliveries.count
  assert_equal @user.email, ActionMailer::Base.deliveries.last.to.first
end

test "calls payment gateway" do
  PaymentGateway.expects(:charge).with(
    amount: 99.99,
    card_token: "tok_123"
  ).returns(OpenStruct.new(id: "ch_123", success: true))

  Payment::ChargeService.new(@user, params: { amount: 99.99, token: "tok_123" }).call
end
```

--------------------------------

## Best Practices

### Testing Guidelines

Follow these testing patterns.

```ruby
# 1. Test validation during initialize, not call
error = assert_raises(ValidationError) do
  Service.new(user, params: bad_params)  # Not .call
end

# 2. Test both success and failure paths
test "success with valid params" do...end
test "failure with invalid params" do...end

# 3. Test authorization for different user types
test "admin can access" do...end
test "owner can access" do...end
test "non-owner cannot access" do...end

# 4. Use fixtures or factories for test data
@user = users(:seller)  # Fixture
@user = create(:seller)  # Factory

# 5. Test side effects
assert_difference "Product.count", 1 do
  service.call
end

# 6. Clean tests - one assertion per logical concept
test "creates product with correct name" do
  result = service.call
  assert_equal "Widget", result.resource.name
end
```

--------------------------------

## Next Steps

### Continue Learning

What to learn next.

```ruby
# Now that you understand testing:

# 1. See complete real-world examples
#    → guide/09-real-world-example.md

# 2. Review API documentation
#    → context7/
```

--------------------------------
