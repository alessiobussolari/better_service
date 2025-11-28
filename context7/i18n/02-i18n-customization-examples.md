# I18n Customization Examples

## Setting Custom Namespace

### Per-Service Namespace

```ruby
class Products::CreateService < BetterService::Services::CreateService
  messages_namespace :products

  respond_with do |data|
    success_result(message("create.success"), data)
  end
end
```

### Module-Level Namespace

```ruby
module Products
  class BaseService < BetterService::Services::Base
    messages_namespace :products
  end

  class CreateService < BaseService
    # Inherits :products namespace
  end

  class UpdateService < BaseService
    # Inherits :products namespace
  end
end
```

## Creating Custom Locale Files

### Using Generator

```bash
rails generate better_service:locale products
```

Creates `config/locales/products.en.yml`:

```yaml
en:
  products:
    services:
      index:
        success: "Products retrieved successfully"
      show:
        success: "Product retrieved successfully"
      create:
        success: "Product created successfully"
      update:
        success: "Product updated successfully"
      destroy:
        success: "Product deleted successfully"
```

### Manual Creation

Create `config/locales/orders.en.yml`:

```yaml
en:
  orders:
    services:
      create:
        success: "Order #%{number} placed successfully!"
        pending: "Order is pending approval"
        error: "Could not create order"
      update:
        success: "Order #%{number} updated"
        shipped: "Order has been shipped!"
      cancel:
        success: "Order cancelled"
        error: "Cannot cancel a shipped order"
      checkout:
        success: "Checkout complete! Thank you for your order."
        payment_failed: "Payment failed. Please try again."
```

## Message Interpolation

### Basic Interpolation

```yaml
# config/locales/products.en.yml
en:
  products:
    services:
      create:
        success: "Product '%{name}' created successfully!"
```

```ruby
class Products::CreateService < BetterService::Services::CreateService
  messages_namespace :products

  respond_with do |data|
    success_result(
      message("create.success", name: data[:resource].name),
      data
    )
  end
end

# Result: "Product 'Awesome Widget' created successfully!"
```

### Multiple Interpolations

```yaml
# config/locales/orders.en.yml
en:
  orders:
    services:
      create:
        success: "Order #%{number} for %{item_count} items totaling %{total} placed!"
```

```ruby
class Orders::CreateService < BetterService::Services::CreateService
  messages_namespace :orders

  respond_with do |data|
    order = data[:resource]
    success_result(
      message("create.success",
        number: order.number,
        item_count: order.items.count,
        total: number_to_currency(order.total)
      ),
      data
    )
  end
end

# Result: "Order #12345 for 3 items totaling $99.99 placed!"
```

### Conditional Messages

```ruby
class Products::UpdateService < BetterService::Services::UpdateService
  messages_namespace :products

  respond_with do |data|
    product = data[:resource]
    key = product.published? ? "update.published" : "update.draft"

    success_result(message(key, name: product.name), data)
  end
end
```

```yaml
en:
  products:
    services:
      update:
        published: "Product '%{name}' is now live!"
        draft: "Product '%{name}' saved as draft"
```

## Overriding Default Messages

### Override All Defaults

Create/update `config/locales/better_service.en.yml`:

```yaml
en:
  better_service:
    services:
      default:
        created: "Successfully created!"
        updated: "Changes saved!"
        deleted: "Permanently removed"
        listed: "Here's what we found"
        shown: "Here are the details"
        action_completed: "Done!"
```

### Localized Defaults

```yaml
# config/locales/better_service.es.yml
es:
  better_service:
    services:
      default:
        created: "Recurso creado exitosamente"
        updated: "Recurso actualizado exitosamente"
        deleted: "Recurso eliminado exitosamente"
        listed: "Recursos recuperados exitosamente"
        shown: "Recurso recuperado exitosamente"
        action_completed: "Acción completada exitosamente"
```

## Multi-Language Support

### English Locale

```yaml
# config/locales/products.en.yml
en:
  products:
    services:
      create:
        success: "Product created successfully!"
      update:
        success: "Product updated!"
      destroy:
        success: "Product deleted"
```

### Spanish Locale

```yaml
# config/locales/products.es.yml
es:
  products:
    services:
      create:
        success: "¡Producto creado con éxito!"
      update:
        success: "¡Producto actualizado!"
      destroy:
        success: "Producto eliminado"
```

### Using in Controller

```ruby
class ProductsController < ApplicationController
  around_action :switch_locale

  def create
    result = Products::CreateService.new(current_user, params: product_params).call
    # Message will be in user's locale
    redirect_to result[:resource], notice: result[:message]
  end

  private

  def switch_locale(&action)
    locale = current_user&.locale || I18n.default_locale
    I18n.with_locale(locale, &action)
  end
end
```

## Error Messages

### Custom Error Messages

```yaml
# config/locales/products.en.yml
en:
  products:
    services:
      errors:
        not_found: "Product not found"
        unauthorized: "You cannot modify this product"
        out_of_stock: "Product is out of stock"
        invalid_quantity: "Quantity must be at least %{minimum}"
```

### Using in Service

```ruby
class Products::PurchaseService < BetterService::Services::ActionService
  messages_namespace :products

  process_with do |data|
    product = data[:resource]

    if product.quantity < params[:quantity]
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("errors.out_of_stock"),
        code: :out_of_stock
      )
    end

    # ...
  end
end
```

## ActionService Custom Actions

```yaml
# config/locales/products.en.yml
en:
  products:
    services:
      publish:
        success: "Product is now published and visible to customers"
        already_published: "Product is already published"
      unpublish:
        success: "Product has been unpublished"
      archive:
        success: "Product has been archived"
      restore:
        success: "Product has been restored from archive"
      duplicate:
        success: "Product '%{name}' has been duplicated as '%{new_name}'"
```

```ruby
class Products::PublishService < BetterService::Services::ActionService
  messages_namespace :products
  action_name :published

  respond_with do |data|
    success_result(message("publish.success"), data)
  end
end

class Products::DuplicateService < BetterService::Services::ActionService
  messages_namespace :products
  action_name :duplicated

  respond_with do |data|
    success_result(
      message("duplicate.success",
        name: data[:original].name,
        new_name: data[:resource].name
      ),
      data
    )
  end
end
```

## Workflows Messages

```yaml
# config/locales/checkout.en.yml
en:
  checkout:
    workflow:
      started: "Processing your order..."
      payment_processing: "Processing payment..."
      payment_success: "Payment successful!"
      shipping_calculated: "Shipping calculated: %{cost}"
      order_created: "Order #%{number} created"
      confirmation_sent: "Confirmation email sent to %{email}"
      complete: "Thank you for your order!"
```

```ruby
class Checkout::WorkflowWithMessages < BetterService::Workflows::Base
  def translate(key, **options)
    I18n.t("checkout.workflow.#{key}", **options)
  end

  step :create_order,
       with: Orders::CreateService,
       after: ->(ctx) {
         puts translate("order_created", number: ctx.create_order.number)
       }
end
```

## Testing I18n

### Test Message Lookup

```ruby
class Products::CreateServiceTest < ActiveSupport::TestCase
  test "returns localized success message" do
    I18n.with_locale(:en) do
      result = Products::CreateService.new(
        users(:admin),
        params: { name: "Widget", price: 10.00 }
      ).call

      assert_equal "Product created successfully!", result[:message]
    end
  end

  test "returns Spanish message when locale is es" do
    I18n.with_locale(:es) do
      result = Products::CreateService.new(
        users(:admin),
        params: { name: "Widget", price: 10.00 }
      ).call

      assert_equal "¡Producto creado con éxito!", result[:message]
    end
  end
end
```

### Test Fallback

```ruby
test "falls back to default message when custom not found" do
  # Without custom locale file
  service_class = Class.new(BetterService::Services::CreateService) do
    messages_namespace :nonexistent

    schema do
      required(:name).filled(:string)
    end

    search_with { {} }
    process_with { |_| { resource: OpenStruct.new(name: "Test") } }

    respond_with do |data|
      success_result(message("create.success"), data)
    end
  end

  result = service_class.new(users(:admin), params: { name: "Test" }).call

  # Falls back to better_service.services.default.created
  assert_equal "Resource created successfully", result[:message]
end
```
