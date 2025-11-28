# BetterService FAQ Examples

This document provides detailed code examples answering the most common questions about BetterService. Each section includes complete, working code with explanations.

---

## Table of Contents

1. [Schema Validation with Dry::Schema](#q1-schema-validation-with-dryschema)
2. [Authorization with authorize_with](#q2-authorization-with-authorize_with)
3. [Create Service with process/respond Phases](#q3-create-service-with-processrespond-phases)
4. [Pure Exception Pattern](#q4-pure-exception-pattern)
5. [Transaction with Rollback](#q5-transaction-with-rollback)
6. [Workflow with Service Composition](#q6-workflow-with-service-composition)
7. [Cache Management](#q7-cache-management)
8. [Generator Scaffold](#q8-generator-scaffold)
9. [Conditional Branching Workflow with Rollback](#q9-conditional-branching-workflow-with-rollback)
10. [Multi-Layered Authorization](#q10-multi-layered-authorization)

---

## Q1: Schema Validation with Dry::Schema

**Objective:** Define input schema to validate parameters using Dry::Schema DSL.

### Code Example

```ruby
class Products::CreateService < BetterService::CreateService
  schema do
    required(:name).filled(:string, min_size?: 3)
    required(:price).filled(:decimal, gt?: 0)
    optional(:description).maybe(:string)
    optional(:category_id).maybe(:integer)
    required(:status).filled(:string, included_in?: %w[draft published])
  end

  process_with do |data|
    product = user.products.create!(params)
    { resource: product }
  end
end
```

### Key Points

- `required()` - Parameter must be present
- `optional()` - Parameter can be omitted
- `.filled()` - Value must not be empty
- `.maybe()` - Value can be nil
- Type constraints: `:string`, `:integer`, `:decimal`, `:date`, `:bool`
- Validation predicates: `min_size?`, `max_size?`, `gt?`, `lt?`, `gteq?`, `lteq?`, `included_in?`

### Usage

```ruby
# Valid params
service = Products::CreateService.new(user, params: {
  name: "Widget Pro",
  price: 99.99,
  status: "draft"
})
result = service.call
# => { success: true, resource: #<Product...>, metadata: { action: :created } }

# Invalid params - raises ValidationError during initialize
service = Products::CreateService.new(user, params: {
  name: "AB",           # Too short (min_size: 3)
  price: -10,           # Not greater than 0
  status: "unknown"     # Not in allowed values
})
# => raises BetterService::Errors::Runtime::ValidationError
```

### Error Handling

```ruby
begin
  service = Products::CreateService.new(user, params: invalid_params)
rescue BetterService::Errors::Runtime::ValidationError => e
  e.code                    # => :validation_failed
  e.context[:validation_errors]
  # => { name: ["size cannot be less than 3"], price: ["must be greater than 0"] }
end
```

---

## Q2: Authorization with authorize_with

**Objective:** Integrate authorization rules into services.

### Code Example

```ruby
class Products::UpdateService < BetterService::UpdateService
  schema do
    required(:id).filled(:integer)
    required(:name).filled(:string)
  end

  authorize_with do
    # `user` is automatically available
    product = Product.find(params[:id])
    user.admin? || product.user_id == user.id
  end

  process_with do |data|
    product = Product.find(params[:id])
    product.update!(params.except(:id))
    { resource: product }
  end
end
```

### Key Points

- `authorize_with` block runs **before** `search_with` (fail-fast)
- Block must return truthy value for authorization to pass
- `user` object is automatically available
- `params` hash is available for context-based authorization

### Allow Nil User

For public endpoints that don't require authentication:

```ruby
class Products::IndexService < BetterService::IndexService
  allow_nil_user  # Skip nil user check

  schema do
    optional(:category_id).maybe(:integer)
  end

  search_with do
    { items: Product.published.to_a }
  end
end
```

### Usage

```ruby
# Authorized user
service = Products::UpdateService.new(owner_user, params: { id: 1, name: "New Name" })
result = service.call
# => { success: true, resource: #<Product...> }

# Unauthorized user
service = Products::UpdateService.new(other_user, params: { id: 1, name: "New Name" })
service.call
# => raises BetterService::Errors::Runtime::AuthorizationError
```

### Error Handling

```ruby
begin
  service.call
rescue BetterService::Errors::Runtime::AuthorizationError => e
  e.code     # => :unauthorized
  e.message  # => "Not authorized to perform this action"
  e.context  # => { service: "Products::UpdateService", user_id: 123 }
end
```

---

## Q3: Create Service with process/respond Phases

**Objective:** Demonstrate the 5-phase service flow with process and respond phases.

### Code Example

```ruby
class Orders::CreateService < BetterService::CreateService
  schema do
    required(:product_id).filled(:integer)
    required(:quantity).filled(:integer, gt?: 0)
  end

  # Phase 3: Process - creates the resource
  process_with do |data|
    product = Product.find(params[:product_id])
    order = user.orders.create!(
      product: product,
      quantity: params[:quantity],
      total: product.price * params[:quantity]
    )
    { resource: order, metadata: { product_name: product.name } }
  end

  # Phase 5: Respond - formats the response
  respond_with do |result|
    {
      success: true,
      message: message("create.success"),
      order: result[:resource].as_json,
      metadata: result[:metadata]
    }
  end
end
```

### 5-Phase Flow

| Phase | Method | Purpose |
|-------|--------|---------|
| 1 | `initialize` | Schema validation (Dry::Schema) |
| 2 | `authorize` | Authorization check (`authorize_with`) |
| 3 | `search` | Load data (`search_with`) |
| 4 | `process` | Transform/create (`process_with`) |
| 5 | `respond` | Format response (`respond_with`) |

### Usage

```ruby
service = Orders::CreateService.new(user, params: {
  product_id: 123,
  quantity: 2
})

result = service.call
# => {
#   success: true,
#   message: "Order created successfully",
#   order: { id: 1, quantity: 2, total: 199.98, ... },
#   metadata: { action: :created, product_name: "Widget Pro" }
# }
```

---

## Q4: Pure Exception Pattern

**Objective:** Handle errors using exceptions with rich context.

### Code Example

```ruby
class Payments::ProcessService < BetterService::ActionService
  schema do
    required(:order_id).filled(:integer)
    required(:amount).filled(:decimal, gt?: 0)
  end

  process_with do |data|
    order = Order.find(params[:order_id])

    # Business logic exception
    if order.paid?
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Order already paid",
        code: :order_already_paid,
        context: { order_id: order.id }
      )
    end

    begin
      payment = PaymentGateway.charge(order, params[:amount])
      { resource: payment }
    rescue PaymentGateway::Error => e
      # Wrap external error
      raise BetterService::Errors::Runtime::ExecutionError.new(
        "Payment failed: #{e.message}",
        code: :payment_failed,
        original_error: e,
        context: { order_id: order.id, amount: params[:amount] }
      )
    end
  end
end
```

### Controller Usage

```ruby
class PaymentsController < ApplicationController
  def create
    result = Payments::ProcessService.new(current_user, params: payment_params).call
    render json: result
  rescue BetterService::Errors::Runtime::ValidationError => e
    render json: { error: e.message, code: e.code }, status: :unprocessable_entity
  rescue BetterService::Errors::Runtime::ExecutionError => e
    render json: { error: e.message, code: e.code }, status: :service_unavailable
  end
end
```

### Exception Hierarchy

```
BetterService::BetterServiceError
├── Errors::Configuration::ConfigurationError
│   ├── SchemaRequiredError
│   ├── NilUserError
│   ├── InvalidSchemaError
│   └── InvalidConfigurationError
├── Errors::Runtime::RuntimeError
│   ├── ValidationError
│   ├── AuthorizationError
│   ├── ExecutionError
│   ├── ResourceNotFoundError
│   ├── TransactionError
│   └── DatabaseError
└── Errors::Workflowable::Runtime::WorkflowRuntimeError
    ├── WorkflowExecutionError
    ├── StepExecutionError
    └── RollbackError
```

### Exception Methods

| Method | Description |
|--------|-------------|
| `message` | Human-readable error message |
| `code` | Symbol code (`:validation_failed`, `:unauthorized`, etc.) |
| `context` | Hash with service-specific context |
| `original_error` | Original exception if wrapping |
| `timestamp` | When the error occurred |
| `to_h` | Structured hash representation |
| `detailed_message` | Extended message with context |

---

## Q5: Transaction with Rollback

**Objective:** Perform multiple operations with automatic rollback on failure.

### Code Example

```ruby
class Orders::CheckoutService < BetterService::CreateService
  # Transaction enabled by default for CreateService
  # For other types: with_transaction true

  schema do
    required(:cart_id).filled(:integer)
    required(:shipping_address_id).filled(:integer)
  end

  process_with do |data|
    cart = Cart.find(params[:cart_id])
    address = Address.find(params[:shipping_address_id])

    # All operations are wrapped in a transaction
    order = user.orders.create!(
      status: :pending,
      shipping_address: address
    )

    cart.items.each do |item|
      # If this fails, everything rolls back
      order.line_items.create!(
        product: item.product,
        quantity: item.quantity,
        price: item.product.price
      )

      # Decrement stock (raises if insufficient)
      item.product.decrement!(:stock, item.quantity)
    end

    # Calculate total
    order.update!(total: order.line_items.sum(&:subtotal))

    # Clear cart
    cart.items.destroy_all

    { resource: order }
  end
end
```

### Transaction Configuration

```ruby
# Enable transactions (default for Create/Update/Destroy)
class MyService < BetterService::ActionService
  with_transaction true
end

# Disable transactions
class MyService < BetterService::CreateService
  with_transaction false
end
```

### Usage

```ruby
service = Orders::CheckoutService.new(user, params: {
  cart_id: 123,
  shipping_address_id: 456
})

begin
  result = service.call
  # => { success: true, resource: #<Order...>, metadata: { action: :created } }
rescue BetterService::Errors::Runtime::TransactionError => e
  # All database changes rolled back
  e.code            # => :transaction_error
  e.original_error  # => Original exception that caused rollback
end
```

---

## Q6: Workflow with Service Composition

**Objective:** Pass output from one service to the next in a workflow.

### Code Example

```ruby
class Orders::PurchaseWorkflow < BetterService::Workflows::Base
  step :validate_cart,
       with: Cart::ValidateService,
       input: ->(ctx) { { cart_id: ctx.cart_id } }

  step :calculate_total,
       with: Orders::CalculateTotalService,
       input: ->(ctx) {
         {
           items: ctx.validate_cart[:items],
           discount_code: ctx.discount_code
         }
       }

  step :process_payment,
       with: Payments::ChargeService,
       input: ->(ctx) {
         {
           amount: ctx.calculate_total[:total],
           user_id: ctx.user.id
         }
       }

  step :create_order,
       with: Orders::CreateService,
       input: ->(ctx) {
         {
           cart_id: ctx.cart_id,
           payment_id: ctx.process_payment[:id],
           total: ctx.calculate_total[:total]
         }
       }
end
```

### Usage

```ruby
result = Orders::PurchaseWorkflow.new(
  current_user,
  params: { cart_id: 123, discount_code: "SAVE10" }
).call

# Access results from each step
result[:context].validate_cart    # Output from step 1
result[:context].calculate_total  # Output from step 2
result[:context].process_payment  # Output from step 3
result[:context].create_order     # Output from step 4

# Metadata
result[:metadata][:steps_executed]
# => [:validate_cart, :calculate_total, :process_payment, :create_order]
```

### Step Options

| Option | Description |
|--------|-------------|
| `with:` | Service class to execute |
| `input:` | Lambda to build params from context |
| `optional:` | If true, failure doesn't stop workflow |
| `rollback:` | Lambda to undo step on failure |

---

## Q7: Cache Management

**Objective:** Implement caching with automatic invalidation.

### Code Example

```ruby
class Products::IndexService < BetterService::IndexService
  # Cache configuration
  cache_key "products_index"
  cache_ttl 15.minutes
  cache_contexts :products  # For invalidation

  schema do
    optional(:category_id).maybe(:integer)
    optional(:page).filled(:integer, gt?: 0)
  end

  search_with do
    products = user.products
    products = products.where(category_id: params[:category_id]) if params[:category_id]
    products = products.page(params[:page] || 1).per(20)
    { items: products.to_a }
  end
end

# Service that invalidates cache
class Products::CreateService < BetterService::CreateService
  cache_contexts :products  # Invalidates this context

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal)
  end

  process_with do |data|
    product = user.products.create!(params)
    { resource: product }
    # Cache "products" invalidated automatically after success
  end
end
```

### Manual Invalidation

```ruby
# Invalidate for specific user
BetterService::CacheService.invalidate_for_context(user, "products")

# Invalidate for all users
BetterService::CacheService.invalidate_global("products")
```

### Cache Configuration DSL

| DSL Method | Description |
|------------|-------------|
| `cache_key` | Base key for caching |
| `cache_ttl` | Time-to-live duration |
| `cache_contexts` | Context names for invalidation |
| `auto_invalidate_cache false` | Disable auto-invalidation |

### Usage

```ruby
# First call - hits database, caches result
result1 = Products::IndexService.new(user, params: { category_id: 5 }).call

# Second call - returns cached result
result2 = Products::IndexService.new(user, params: { category_id: 5 }).call

# Create product - automatically invalidates "products" cache
Products::CreateService.new(user, params: { name: "New", price: 99 }).call

# Next call - cache miss, hits database again
result3 = Products::IndexService.new(user, params: { category_id: 5 }).call
```

---

## Q8: Generator Scaffold

**Objective:** Generate services using Rails CLI generators.

### Commands

```bash
# Generate all CRUD services for User
rails generate serviceable:scaffold User

# Output:
#   create  app/services/users/index_service.rb
#   create  app/services/users/show_service.rb
#   create  app/services/users/create_service.rb
#   create  app/services/users/update_service.rb
#   create  app/services/users/destroy_service.rb
#   create  test/services/users/index_service_test.rb
#   create  test/services/users/show_service_test.rb
#   create  test/services/users/create_service_test.rb
#   create  test/services/users/update_service_test.rb
#   create  test/services/users/destroy_service_test.rb

# With presenter
rails generate serviceable:scaffold Product --presenter

# Generate single service
rails generate serviceable:update User

# Generate custom action service
rails generate serviceable:action User activate

# Generate workflow
rails generate workflowable:workflow Order::Purchase
```

### Generated File Structure

```ruby
# app/services/users/update_service.rb
class Users::UpdateService < BetterService::UpdateService
  model_class User

  schema do
    required(:id).filled(:integer)
    # Add fields here
  end

  authorize_with do
    # Add authorization logic
    true
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

### Available Generators

| Generator | Description |
|-----------|-------------|
| `serviceable:scaffold Model` | All 5 CRUD services + tests |
| `serviceable:index Model` | Index service |
| `serviceable:show Model` | Show service |
| `serviceable:create Model` | Create service |
| `serviceable:update Model` | Update service |
| `serviceable:destroy Model` | Destroy service |
| `serviceable:action Model action_name` | Custom action service |
| `workflowable:workflow Name` | Workflow class |
| `better_service:presenter Model` | Presenter class |
| `better_service:install` | Initializer + locale file |
| `better_service:locale namespace` | Custom locale file |

---

## Q9: Conditional Branching Workflow with Rollback

**Objective:** Implement conditional branching with automatic rollback on failure.

### Code Example

```ruby
class Orders::ProcessWorkflow < BetterService::Workflows::Base
  with_transaction true

  step :validate_order,
       with: Orders::ValidateService,
       input: ->(ctx) { { order_id: ctx.order_id } }

  # Branch based on payment method
  branch do
    on ->(ctx) { ctx.validate_order[:payment_method] == "credit_card" } do
      step :charge_card,
           with: Payments::ChargeCreditCardService,
           input: ->(ctx) { { order: ctx.validate_order } },
           rollback: ->(ctx) {
             Payments::RefundService.new(ctx.user, params: {
               charge_id: ctx.charge_card[:id]
             }).call
           }

      step :verify_3d_secure,
           with: Payments::Verify3DSecureService,
           input: ->(ctx) { { charge: ctx.charge_card } },
           optional: true
    end

    on ->(ctx) { ctx.validate_order[:payment_method] == "paypal" } do
      step :paypal_checkout,
           with: Payments::PaypalCheckoutService,
           input: ->(ctx) { { order: ctx.validate_order } },
           rollback: ->(ctx) {
             Payments::PaypalRefundService.new(ctx.user, params: {
               paypal_order_id: ctx.paypal_checkout[:id]
             }).call
           }
    end

    otherwise do
      step :mark_pending,
           with: Orders::MarkPendingService,
           input: ->(ctx) { { order: ctx.validate_order } }
    end
  end

  # Steps after branch (always executed)
  step :send_confirmation,
       with: Notifications::OrderConfirmationService,
       input: ->(ctx) { { order_id: ctx.order_id } }

  step :update_inventory,
       with: Inventory::DecrementService,
       input: ->(ctx) { { order: ctx.validate_order } },
       rollback: ->(ctx) {
         Inventory::RestoreService.new(ctx.user, params: {
           order: ctx.validate_order
         }).call
       }
end
```

### Usage

```ruby
result = Orders::ProcessWorkflow.new(
  current_user,
  params: { order_id: 123 }
).call

# Metadata shows which branch was taken
result[:metadata][:branches_taken]
# => ["branch_1:on_1"]  # Credit card path
# => ["branch_1:on_2"]  # PayPal path
# => ["branch_1:otherwise"]  # Default path
```

### Branch DSL

| Method | Description |
|--------|-------------|
| `branch do ... end` | Define a branch block |
| `on ->(ctx) { condition } do ... end` | Conditional branch |
| `otherwise do ... end` | Default branch (optional) |

### Rollback Behavior

1. **First-match wins** - Only one branch executes
2. **Rollback in reverse** - Only executed steps are rolled back
3. **Transaction wrapping** - All changes rolled back on failure

### Nested Branches

```ruby
branch do
  on ->(ctx) { ctx.type == "contract" } do
    step :legal_review, with: Legal::ReviewService

    # Nested branch
    branch do
      on ->(ctx) { ctx.legal_review[:value] > 100_000 } do
        step :ceo_approval, with: Approval::CEOService
      end

      otherwise do
        step :manager_approval, with: Approval::ManagerService
      end
    end
  end

  otherwise do
    step :standard_approval, with: Approval::StandardService
  end
end
```

---

## Q10: Multi-Layered Authorization

**Objective:** Implement complex, dynamic authorization with multiple layers.

### Base Service with Authorization Layers

```ruby
class BaseAuthorizedService < BetterService::Services::Base
  class << self
    attr_accessor :authorization_rules
  end

  def self.authorize_with_policy(policy_class)
    @authorization_rules ||= []
    @authorization_rules << { type: :policy, class: policy_class }
  end

  def self.authorize_with_role(*roles)
    @authorization_rules ||= []
    @authorization_rules << { type: :role, roles: roles }
  end

  def self.authorize_with_ownership(field: :user_id)
    @authorization_rules ||= []
    @authorization_rules << { type: :ownership, field: field }
  end
end
```

### Service with Multi-Layer Authorization

```ruby
class Documents::UpdateService < BaseAuthorizedService
  # Layer 1: User role check
  authorize_with_role :admin, :editor

  # Layer 2: Policy object
  authorize_with_policy DocumentPolicy

  # Layer 3: Ownership check
  authorize_with_ownership field: :author_id

  schema do
    required(:id).filled(:integer)
    required(:title).filled(:string)
    optional(:content).maybe(:string)
  end

  # Override authorize for custom logic
  authorize_with do
    document = Document.find(params[:id])

    # Check all layers
    self.class.authorization_rules.all? do |rule|
      case rule[:type]
      when :role
        rule[:roles].any? { |r| user.has_role?(r) }
      when :policy
        rule[:class].new(user, document).update?
      when :ownership
        document.send(rule[:field]) == user.id
      end
    end
  end

  process_with do |data|
    document = Document.find(params[:id])
    document.update!(params.except(:id))
    { resource: document }
  end
end
```

### Policy Class

```ruby
class DocumentPolicy
  attr_reader :user, :document

  def initialize(user, document)
    @user = user
    @document = document
  end

  def update?
    return true if user.admin?
    return true if document.department_id == user.department_id
    return true if document.collaborators.include?(user)
    false
  end

  def destroy?
    user.admin? || document.author_id == user.id
  end
end
```

### Dynamic Authorization Based on Context

```ruby
class Reports::GenerateService < BetterService::ActionService
  schema do
    required(:report_type).filled(:string)
    required(:date_range).hash do
      required(:start_date).filled(:date)
      required(:end_date).filled(:date)
    end
  end

  authorize_with do
    # Dynamic authorization based on report type
    case params[:report_type]
    when "financial"
      user.has_permission?(:view_financial_reports)
    when "hr"
      user.has_permission?(:view_hr_reports) || user.hr_manager?
    when "sales"
      user.sales_team? || user.admin?
    else
      false
    end
  end

  process_with do |data|
    report = ReportGenerator.generate(
      type: params[:report_type],
      range: params[:date_range],
      user: user
    )
    { resource: report }
  end
end
```

### Usage

```ruby
# Admin user - passes all layers
service = Documents::UpdateService.new(admin_user, params: { id: 1, title: "New" })
result = service.call  # => success

# Editor without ownership - fails ownership check
service = Documents::UpdateService.new(editor_user, params: { id: 1, title: "New" })
service.call
# => raises BetterService::Errors::Runtime::AuthorizationError

# Author with viewer role - fails role check
service = Documents::UpdateService.new(author_user, params: { id: 1, title: "New" })
service.call
# => raises BetterService::Errors::Runtime::AuthorizationError
```

---

## See Also

- [Services Overview](/context7/services/01-services-overview.md)
- [Workflows Guide](/context7/workflows/01-workflows-overview.md)
- [Error Handling](/docs/advanced/error-handling.md)
- [Presenters Guide](/docs/advanced/presenters.md)
- [Repository Pattern](/docs/advanced/repository.md)
