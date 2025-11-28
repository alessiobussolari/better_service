# I18n System Overview

BetterService provides built-in internationalization (I18n) support for service messages through the **Messageable** concern.

## How It Works

### The `message()` Helper

Services include a `message()` helper method for retrieving translated messages:

```ruby
class Products::CreateService < BetterService::Services::CreateService
  respond_with do |data|
    success_result(message("create.success"), data)
  end
end
```

### 3-Level Fallback Chain

Messages are looked up in three levels:

1. **Custom namespace** (if defined) - `{namespace}.services.{key_path}`
2. **Default BetterService messages** - `better_service.services.default.{action}`
3. **Key itself** - Returns the key if no translation found

```ruby
# With namespace :products
message("create.success")

# Lookup order:
# 1. products.services.create.success
# 2. better_service.services.default.created
# 3. "create.success"
```

## Default Messages

BetterService provides default messages in `config/locales/better_service.en.yml`:

```yaml
en:
  better_service:
    services:
      default:
        created: "Resource created successfully"
        updated: "Resource updated successfully"
        deleted: "Resource deleted successfully"
        listed: "Resources retrieved successfully"
        shown: "Resource retrieved successfully"
        action_completed: "Action completed successfully"

      errors:
        validation_failed: "Validation failed"
        unauthorized: "You are not authorized to perform this action"
        not_found: "Resource not found"
        database_error: "A database error occurred"
        execution_error: "An error occurred while processing your request"
```

## Action Name Mapping

The `message()` helper maps key paths to default actions:

| Key Path | Default Action |
|----------|----------------|
| `create` or `create.*` | `created` |
| `update` or `update.*` | `updated` |
| `destroy`, `delete` | `deleted` |
| `index`, `list` | `listed` |
| `show` | `shown` |
| Other | `action_completed` |

## Basic Usage

### Using Default Messages

```ruby
class Products::CreateService < BetterService::Services::CreateService
  respond_with do |data|
    # Uses: better_service.services.default.created
    # => "Resource created successfully"
    success_result(message("create.success"), data)
  end
end
```

### With Custom Namespace

```ruby
class Products::CreateService < BetterService::Services::CreateService
  messages_namespace :products

  respond_with do |data|
    # Looks up: products.services.create.success
    # Falls back to: better_service.services.default.created
    success_result(message("create.success"), data)
  end
end
```

### With Interpolation

```ruby
class Products::CreateService < BetterService::Services::CreateService
  messages_namespace :products

  respond_with do |data|
    # products.services.create.success: "Product %{name} created!"
    success_result(
      message("create.success", name: data[:resource].name),
      data
    )
  end
end
```

## Locale File Structure

### Default Locale (`config/locales/better_service.en.yml`)

```yaml
en:
  better_service:
    services:
      default:
        created: "Resource created successfully"
        updated: "Resource updated successfully"
        deleted: "Resource deleted successfully"
        listed: "Resources retrieved successfully"
        shown: "Resource retrieved successfully"
        action_completed: "Action completed successfully"
```

### Custom Namespace Locale (`config/locales/products.en.yml`)

```yaml
en:
  products:
    services:
      create:
        success: "Product created successfully!"
        error: "Failed to create product"
      update:
        success: "Product updated!"
        error: "Failed to update product"
      destroy:
        success: "Product deleted"
      index:
        success: "Products loaded"
      show:
        success: "Product found"
```

## Service Examples

### IndexService

```ruby
class Products::IndexService < BetterService::Services::IndexService
  messages_namespace :products

  respond_with do |data|
    {
      success: true,
      message: message("index.success"),  # => "Products loaded"
      items: data[:items],
      metadata: { action: :listed }
    }
  end
end
```

### CreateService

```ruby
class Products::CreateService < BetterService::Services::CreateService
  messages_namespace :products

  respond_with do |data|
    success_result(
      message("create.success"),  # => "Product created successfully!"
      data
    )
  end
end
```

### UpdateService

```ruby
class Products::UpdateService < BetterService::Services::UpdateService
  messages_namespace :products

  respond_with do |data|
    success_result(
      message("update.success"),  # => "Product updated!"
      data
    )
  end
end
```

### DestroyService

```ruby
class Products::DestroyService < BetterService::Services::DestroyService
  messages_namespace :products

  respond_with do |data|
    success_result(
      message("destroy.success"),  # => "Product deleted"
      data
    )
  end
end
```

## Generator Support

Generate custom locale files:

```bash
rails generate better_service:locale products
```

Creates `config/locales/products.en.yml` with template structure.

## Next Steps

- [I18n Customization](./02-i18n-customization-examples.md) - Advanced customization examples
