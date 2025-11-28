# RepositoryAware Concern

## Basic Usage

Include the concern and declare repositories:

```ruby
class Products::IndexService < BetterService::Services::IndexService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product

  search_with do
    { items: product_repository.all.to_a }
  end
end
```

## DSL Options

### Standard Declaration

```ruby
repository :product
```

- Creates private method: `product_repository`
- Derives class name: `ProductRepository`
- Memoized: Same instance returned on multiple calls

### Custom Class Name

```ruby
repository :product, class_name: "Inventory::ProductRepository"
```

- Creates private method: `product_repository`
- Uses explicit class: `Inventory::ProductRepository`

### Custom Accessor Name

```ruby
repository :product, as: :products
```

- Creates private method: `products`
- Derives class name: `ProductRepository`

### Combined Options

```ruby
repository :user, class_name: "Admin::UserRepository", as: :admin_users
```

- Creates private method: `admin_users`
- Uses explicit class: `Admin::UserRepository`

## Service Examples

### IndexService with Repository

```ruby
class Products::IndexService < BetterService::Services::IndexService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product

  schema do
    optional(:page).filled(:integer)
    optional(:per_page).filled(:integer)
    optional(:category_id).filled(:integer)
  end

  search_with do
    predicates = {}
    predicates[:category_id_eq] = params[:category_id] if params[:category_id]

    items = product_repository.search(
      predicates,
      page: params[:page] || 1,
      per_page: params[:per_page] || 20,
      includes: [:category]
    )

    { items: items.to_a, total: items.total_count }
  end

  process_with do |data|
    {
      items: data[:items],
      metadata: {
        total: data[:total],
        page: params[:page] || 1
      }
    }
  end
end
```

### ShowService with Repository

```ruby
class Products::ShowService < BetterService::Services::ShowService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    product = product_repository.find(params[:id])
    { resource: product }
  end
end
```

### CreateService with Repository

```ruby
class Products::CreateService < BetterService::Services::CreateService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal)
    optional(:description).filled(:string)
    optional(:published).filled(:bool)
  end

  search_with { {} }

  process_with do |_data|
    product = product_repository.create!(
      name: params[:name],
      price: params[:price],
      description: params[:description],
      published: params[:published] || false,
      user_id: user.id
    )

    { resource: product }
  end
end
```

### UpdateService with Repository

```ruby
class Products::UpdateService < BetterService::Services::UpdateService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product

  schema do
    required(:id).filled(:integer)
    optional(:name).filled(:string)
    optional(:price).filled(:decimal)
    optional(:description).filled(:string)
    optional(:published).filled(:bool)
  end

  search_with do
    product = product_repository.find(params[:id])
    { resource: product }
  end

  process_with do |data|
    update_attrs = params.slice(:name, :price, :description, :published).compact
    updated_product = product_repository.update(data[:resource], update_attrs)
    { resource: updated_product }
  end
end
```

### DestroyService with Repository

```ruby
class Products::DestroyService < BetterService::Services::DestroyService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product

  search_with do
    product = product_repository.find(params[:id])
    { resource: product }
  end

  process_with do |data|
    product_repository.destroy(data[:resource])
    { resource: data[:resource] }
  end
end
```

## Multiple Repositories

### Two Repositories

```ruby
class Orders::CreateService < BetterService::Services::CreateService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :order
  repository :product

  schema do
    required(:product_id).filled(:integer)
    required(:quantity).filled(:integer)
  end

  search_with do
    product = product_repository.find(params[:product_id])
    { product: product }
  end

  process_with do |data|
    order = order_repository.create!(
      product: data[:product],
      quantity: params[:quantity],
      total: data[:product].price * params[:quantity],
      user_id: user.id
    )

    { resource: order }
  end
end
```

### Dashboard with Multiple Repositories

```ruby
class Dashboard::IndexService < BetterService::Services::IndexService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product, as: :products
  repository :order, as: :orders
  repository :user, as: :users

  search_with do
    {
      recent_products: products.search({}, limit: 5, order: { created_at: :desc }).to_a,
      pending_orders: orders.where(status: "pending").to_a,
      total_users: users.count
    }
  end

  process_with do |data|
    {
      items: [],
      metadata: {
        recent_products: data[:recent_products],
        pending_orders: data[:pending_orders],
        total_users: data[:total_users]
      }
    }
  end
end
```

## Memoization Behavior

Repository instances are memoized per service instance:

```ruby
class MyService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product

  def demonstrate_memoization
    repo1 = product_repository
    repo2 = product_repository
    repo3 = product_repository

    # All return the SAME instance
    repo1.equal?(repo2)  # => true
    repo2.equal?(repo3)  # => true
  end
end
```

**Benefits:**
- Single repository instance per service call
- Efficient memory usage
- Consistent behavior within service lifecycle

## Testing with Repositories

### Mocking Repository in Tests

```ruby
class Products::IndexServiceTest < ActiveSupport::TestCase
  test "returns published products" do
    # Create mock repository
    mock_repo = Minitest::Mock.new
    mock_products = [
      OpenStruct.new(id: 1, name: "Product 1"),
      OpenStruct.new(id: 2, name: "Product 2")
    ]
    mock_repo.expect(:search, mock_products, [Hash, Hash])

    # Inject mock
    service = Products::IndexService.new(user, params: {})
    service.instance_variable_set(:@product_repository, mock_repo)

    result = service.call

    assert result[:success]
    assert_equal 2, result[:items].count
    mock_repo.verify
  end
end
```

### Integration Test with Real Repository

```ruby
class Products::CreateServiceTest < ActiveSupport::TestCase
  test "creates product via repository" do
    user = users(:admin)

    result = Products::CreateService.new(
      user,
      params: { name: "New Widget", price: 29.99 }
    ).call

    assert result[:success]
    assert result[:resource].persisted?
    assert_equal "New Widget", result[:resource].name
    assert_equal user.id, result[:resource].user_id
  end
end
```

## Common Patterns

### Repository with Authorization

```ruby
class Products::UpdateService < BetterService::Services::UpdateService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product

  authorize_with do
    product = product_repository.find(params[:id])
    product.user_id == user.id || user.admin?
  end

  search_with do
    { resource: product_repository.find(params[:id]) }
  end

  # ...
end
```

### Repository with Custom Queries

```ruby
class Reports::SalesService < BetterService::Services::IndexService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :order

  search_with do
    orders = order_repository.completed
                             .in_date_range(params[:start_date], params[:end_date])
                             .by_category(params[:category_id])

    { items: orders.to_a }
  end
end
```

### Repository in ActionService

```ruby
class Products::PublishService < BetterService::Services::ActionService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product

  action_name :published

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: product_repository.find(params[:id]) }
  end

  process_with do |data|
    product_repository.update(data[:resource], published: true, published_at: Time.current)
    { resource: data[:resource].reload }
  end
end
```
