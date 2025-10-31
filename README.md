<div align="center">

# 💎 BetterService

### Clean, powerful Service Objects for Rails

[![Gem Version](https://badge.fury.io/rb/better_service.svg)](https://badge.fury.io/rb/better_service)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)

[Features](#-features) • [Installation](#-installation) • [Quick Start](#-quick-start) • [Usage](#-usage) • [Examples](#-examples)

</div>

---

## ✨ Features

BetterService is a comprehensive Service Objects framework for Rails that brings clean architecture and powerful features to your business logic layer:

- 🎯 **5-Phase Flow Architecture**: Structured flow with search → process → transform → respond → viewer phases
- ✅ **Mandatory Schema Validation**: Built-in [Dry::Schema](https://dry-rb.org/gems/dry-schema/) validation for all params
- 🔄 **Transaction Support**: Automatic database transaction wrapping with rollback
- 🔐 **Flexible Authorization**: `authorize_with` DSL that works with any auth system (Pundit, CanCanCan, custom)
- 📊 **Metadata Tracking**: Automatic action metadata in all service responses
- 🏗️ **Powerful Generators**: 7 generators for rapid scaffolding (scaffold, index, show, create, update, destroy, action)
- 📦 **6 Service Types**: Specialized services for different use cases
- 🎨 **DSL-Based**: Clean, expressive DSL with `search_with`, `process_with`, `authorize_with`, etc.

---

## 📦 Installation

Add this line to your application's Gemfile:

```ruby
gem "better_service"
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install better_service
```

---

## 🚀 Quick Start

### 1. Generate a Service

```bash
# Generate a complete CRUD scaffold
rails generate better_service:scaffold Product

# Or generate individual services
rails generate better_service:create Product
rails generate better_service:update Product
rails generate better_service:action Product publish
```

### 2. Use the Service

```ruby
# Create a product
result = Product::CreateService.new(current_user, params: {
  name: "MacBook Pro",
  price: 2499.99
}).call

if result[:success]
  product = result[:resource]
  # => Product object
  action = result[:metadata][:action]
  # => :created
else
  errors = result[:errors]
  # => { name: ["can't be blank"], price: ["must be greater than 0"] }
end
```

---

## 📚 Usage

### Service Structure

All services follow a 5-phase flow:

```ruby
class Product::CreateService < BetterService::CreateService
  # 1. Schema Validation (mandatory)
  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
  end

  # 2. Authorization (optional)
  authorize_with do
    user.admin? || user.can_create_products?
  end

  # 3. Search Phase - Load data
  search_with do
    { category: Category.find_by(id: params[:category_id]) }
  end

  # 4. Process Phase - Business logic
  process_with do |data|
    product = user.products.create!(params)
    { resource: product }
  end

  # 5. Respond Phase - Format response
  respond_with do |data|
    success_result("Product created successfully", data)
  end
end
```

### Available Service Types

#### 1. 📋 IndexService - List Resources

```ruby
class Product::IndexService < BetterService::IndexService
  schema do
    optional(:page).filled(:integer, gteq?: 1)
    optional(:search).maybe(:string)
  end

  search_with do
    products = user.products
    products = products.where("name LIKE ?", "%#{params[:search]}%") if params[:search]
    { items: products.to_a }
  end

  process_with do |data|
    {
      items: data[:items],
      metadata: {
        total: data[:items].count,
        page: params[:page] || 1
      }
    }
  end
end

# Usage
result = Product::IndexService.new(current_user, params: { search: "MacBook" }).call
products = result[:items]  # => Array of products
```

#### 2. 👁️ ShowService - Show Single Resource

```ruby
class Product::ShowService < BetterService::ShowService
  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: user.products.find(params[:id]) }
  end
end

# Usage
result = Product::ShowService.new(current_user, params: { id: 123 }).call
product = result[:resource]
```

#### 3. ➕ CreateService - Create Resource

```ruby
class Product::CreateService < BetterService::CreateService
  # Transaction enabled by default ✅

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
  end

  process_with do |data|
    product = user.products.create!(params)
    { resource: product }
  end
end

# Usage
result = Product::CreateService.new(current_user, params: {
  name: "iPhone",
  price: 999
}).call
```

#### 4. ✏️ UpdateService - Update Resource

```ruby
class Product::UpdateService < BetterService::UpdateService
  # Transaction enabled by default ✅

  schema do
    required(:id).filled(:integer)
    optional(:price).filled(:decimal, gt?: 0)
  end

  authorize_with do
    product = Product.find(params[:id])
    product.user_id == user.id
  end

  search_with do
    { resource: user.products.find(params[:id]) }
  end

  process_with do |data|
    product = data[:resource]
    product.update!(params.except(:id))
    { resource: product }
  end
end
```

#### 5. ❌ DestroyService - Delete Resource

```ruby
class Product::DestroyService < BetterService::DestroyService
  # Transaction enabled by default ✅

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    product = Product.find(params[:id])
    user.admin? || product.user_id == user.id
  end

  search_with do
    { resource: user.products.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].destroy!
    { resource: data[:resource] }
  end
end
```

#### 6. ⚡ ActionService - Custom Actions

```ruby
class Product::PublishService < BetterService::ActionService
  action_name :publish

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    user.can_publish_products?
  end

  search_with do
    { resource: user.products.find(params[:id]) }
  end

  process_with do |data|
    product = data[:resource]
    product.update!(published: true, published_at: Time.current)
    { resource: product }
  end
end

# Usage
result = Product::PublishService.new(current_user, params: { id: 123 }).call
# => { success: true, resource: <Product>, metadata: { action: :publish } }
```

---

## 🔐 Authorization

BetterService provides a flexible `authorize_with` DSL that works with **any** authorization system:

### Simple Role-Based Authorization

```ruby
class Product::CreateService < BetterService::CreateService
  authorize_with do
    user.admin?
  end
end
```

### Resource Ownership Check

```ruby
class Product::UpdateService < BetterService::UpdateService
  authorize_with do
    product = Product.find(params[:id])
    product.user_id == user.id
  end
end
```

### Pundit Integration

```ruby
class Product::UpdateService < BetterService::UpdateService
  authorize_with do
    ProductPolicy.new(user, Product.find(params[:id])).update?
  end
end
```

### CanCanCan Integration

```ruby
class Product::DestroyService < BetterService::DestroyService
  authorize_with do
    Ability.new(user).can?(:destroy, :product)
  end
end
```

### Authorization Failure

When authorization fails, the service returns:

```ruby
{
  success: false,
  errors: ["Not authorized to perform this action"],
  code: :unauthorized
}
```

---

## 🔄 Transaction Support

Create, Update, and Destroy services have **automatic transaction support** enabled by default:

```ruby
class Product::CreateService < BetterService::CreateService
  # Transactions enabled by default ✅

  process_with do |data|
    product = user.products.create!(params)

    # If anything fails here, the entire transaction rolls back
    ProductHistory.create!(product: product, action: "created")
    NotificationService.notify_admins(product)

    { resource: product }
  end
end
```

### Disable Transactions

```ruby
class Product::CreateService < BetterService::CreateService
  with_transaction false  # Disable transactions

  # ...
end
```

---

## 📊 Metadata

All services automatically include metadata with the action name:

```ruby
result = Product::CreateService.new(user, params: { name: "Test" }).call

result[:metadata]
# => { action: :created }

result = Product::UpdateService.new(user, params: { id: 1, name: "Updated" }).call

result[:metadata]
# => { action: :updated }

result = Product::PublishService.new(user, params: { id: 1 }).call

result[:metadata]
# => { action: :publish }
```

You can add custom metadata in the `process_with` block:

```ruby
process_with do |data|
  {
    resource: product,
    metadata: {
      custom_field: "value",
      processed_at: Time.current
    }
  }
end
```

---

## 🏗️ Generators

BetterService includes 7 powerful generators:

### Scaffold Generator

Generates all 5 CRUD services at once:

```bash
rails generate better_service:scaffold Product
```

Creates:
- `app/services/product/index_service.rb`
- `app/services/product/show_service.rb`
- `app/services/product/create_service.rb`
- `app/services/product/update_service.rb`
- `app/services/product/destroy_service.rb`

### Individual Generators

```bash
# Index service
rails generate better_service:index Product

# Show service
rails generate better_service:show Product

# Create service
rails generate better_service:create Product

# Update service
rails generate better_service:update Product

# Destroy service
rails generate better_service:destroy Product

# Custom action service
rails generate better_service:action Product publish
```

---

## 🎯 Examples

### Complete CRUD Workflow

```ruby
# 1. List products
index_result = Product::IndexService.new(current_user, params: {
  search: "MacBook",
  page: 1
}).call

products = index_result[:items]

# 2. Show a product
show_result = Product::ShowService.new(current_user, params: {
  id: products.first.id
}).call

product = show_result[:resource]

# 3. Create a new product
create_result = Product::CreateService.new(current_user, params: {
  name: "New Product",
  price: 99.99
}).call

new_product = create_result[:resource]

# 4. Update the product
update_result = Product::UpdateService.new(current_user, params: {
  id: new_product.id,
  price: 149.99
}).call

# 5. Publish the product (custom action)
publish_result = Product::PublishService.new(current_user, params: {
  id: new_product.id
}).call

# 6. Delete the product
destroy_result = Product::DestroyService.new(current_user, params: {
  id: new_product.id
}).call
```

### Controller Integration

```ruby
class ProductsController < ApplicationController
  def create
    result = Product::CreateService.new(current_user, params: product_params).call

    if result[:success]
      render json: {
        product: result[:resource],
        message: result[:message],
        metadata: result[:metadata]
      }, status: :created
    else
      render json: {
        errors: result[:errors]
      }, status: :unprocessable_entity
    end
  end

  private

  def product_params
    params.require(:product).permit(:name, :price, :description)
  end
end
```

---

## 🧪 Testing

BetterService includes comprehensive test coverage. Run tests with:

```bash
# Run all tests
bundle exec rake

# Or
bundle exec rake test
```

### Manual Testing

A manual test script is included for hands-on verification:

```bash
cd test/dummy
rails console
load '../../manual_test.rb'
```

This runs 8 comprehensive tests covering all service types with automatic database rollback.

---

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please make sure to:
- Add tests for new features
- Update documentation
- Follow the existing code style

---

## 📄 License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

---

<div align="center">

**Made with ❤️ by [Alessio Bussolari](https://github.com/alessiobussolari)**

[Report Bug](https://github.com/alessiobussolari/better_service/issues) · [Request Feature](https://github.com/alessiobussolari/better_service/issues) · [Documentation](https://github.com/alessiobussolari/better_service)

</div>
