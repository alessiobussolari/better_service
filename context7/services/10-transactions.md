# Transaction Examples

## Automatic Transactions
Create, Update, and Destroy services have automatic transactions.

```ruby
class Order::CreateService < BetterService::CreateService
  # Transactions are ON by default for Create services

  process_with do |data|
    order = Order.create!(user: user, total: params[:total])
    order.items.create!(params[:items])
    Payment.charge!(order.total)

    # If any step fails, everything rolls back automatically
    { resource: order }
  end
end
```

## Transaction Rollback on Error
All changes roll back if an error occurs.

```ruby
class Order::CreateService < BetterService::CreateService
  process_with do |data|
    order = Order.create!(params)  # Created
    order.items.create!(item_params)  # Created

    # This fails - card declined
    Payment.charge!(order.total)  # Raises error

    # Order and items are automatically deleted (rolled back)
    { resource: order }
  end
end

# After error:
# - Order not in database
# - Items not in database
# - Everything rolled back
```

## Enable Transactions for ActionService
ActionService transactions are configurable.

```ruby
class Payment::ProcessService < BetterService::ActionService
  self._transactional = true  # Enable transaction

  process_with do |data|
    payment = Payment.create!(order_id: params[:order_id], amount: params[:amount])
    order = payment.order
    order.update!(status: 'paid')

    # All or nothing - both succeed or both roll back
    { resource: payment }
  end
end
```

## Disable Transactions for Read Operations
Turn off transactions for read-only operations.

```ruby
class Report::GenerateService < BetterService::ActionService
  self._transactional = false  # No transaction needed

  process_with do |data|
    # No database writes, no transaction needed
    report_data = generate_complex_report

    { resource: report_data }
  end
end
```

## Nested Service Transactions
Services called within workflows share the workflow's transaction.

```ruby
# Workflow has a transaction
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService  # Has own transaction
  step :charge_payment, with: Payment::ChargeService  # Has own transaction
end

# If charge_payment fails:
# - Payment transaction rolls back
# - Order creation also rolls back (nested in workflow transaction)
# - Database returns to state before workflow started
```

## Multiple Database Operations
All operations in one transaction.

```ruby
class Product::CreateWithVariantsService < BetterService::CreateService
  process_with do |data|
    # All in one transaction
    product = Product.create!(params.except(:variants))

    params[:variants].each do |variant_params|
      product.variants.create!(variant_params)
    end

    product.create_default_images!

    # If any step fails, product and all variants are rolled back
    { resource: product }
  end
end
```

## Transaction with External API
Transactions don't protect external calls.

```ruby
class Order::CreateService < BetterService::CreateService
  process_with do |data|
    order = Order.create!(params)  # In transaction

    # External API call - NOT in transaction
    # If this succeeds but later steps fail:
    # - Order is rolled back
    # - But external API call already happened
    warehouse_response = WarehouseAPI.reserve_inventory(order)

    order.update!(warehouse_ref: warehouse_response.id)

    { resource: order }
  end
end

# Better approach: use after_commit callback or separate service
```

## Safe External Calls Pattern
External operations after transaction commits.

```ruby
class Order::CreateService < BetterService::CreateService
  process_with do |data|
    order = Order.create!(params)
    order.items.create!(item_params)

    # Transaction commits here if no errors
    { resource: order }
  end
end

# Then in workflow:
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService
  # Order transaction commits here

  step :notify_warehouse, with: Warehouse::NotifyService
  # If this fails, order stays created (already committed)
end
```

## Transaction Savepoints
Services use savepoints when nested.

```ruby
class ParentService < BetterService::CreateService
  process_with do |data|
    ActiveRecord::Base.transaction do  # Outer transaction
      parent = Parent.create!(params)

      # Nested service creates savepoint
      child_service = ChildService.new(user, params: {}).call

      parent
    end
  end
end
```
