# IndexService Examples

## Basic List
Retrieve all records of a model.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  schema do
    optional(:page).filled(:integer, gteq?: 1)
    optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
  end

  search_with do
    { items: model_class.all }
  end
end

# Usage
result = Product::IndexService.new(current_user, params: {}).call
products = result[:items]
```

## With Search Filter
Filter records by search term.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  schema do
    optional(:search).maybe(:string)
  end

  search_with do
    scope = model_class.all
    scope = scope.where('name ILIKE ?', "%#{params[:search]}%") if params[:search]
    { items: scope }
  end
end

# Usage
result = Product::IndexService.new(current_user, params: { search: 'laptop' }).call
```

## With Multiple Filters
Combine multiple filter parameters.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  schema do
    optional(:status).maybe(:string, included_in?: %w[active inactive])
    optional(:category_id).maybe(:integer)
    optional(:min_price).maybe(:decimal)
  end

  search_with do
    scope = model_class.all
    scope = scope.where(status: params[:status]) if params[:status]
    scope = scope.where(category_id: params[:category_id]) if params[:category_id]
    scope = scope.where('price >= ?', params[:min_price]) if params[:min_price]
    { items: scope }
  end
end
```

## With Cache
Enable automatic caching for performance.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product
  cache_contexts :products

  schema do
    optional(:category_id).maybe(:integer)
  end

  search_with do
    scope = model_class.all
    scope = scope.where(category_id: params[:category_id]) if params[:category_id]
    { items: scope }
  end
end

# Results are automatically cached by user and params
```

## With Presenter
Format output using a presenter.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product
  presenter ProductPresenter

  search_with do
    { items: model_class.includes(:category).all }
  end
end

# ProductPresenter
class ProductPresenter
  def self.present(product)
    {
      id: product.id,
      name: product.name,
      price: product.price.to_f,
      category: product.category.name
    }
  end
end
```

## With Eager Loading
Avoid N+1 queries with includes.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  search_with do
    {
      items: model_class
        .includes(:category, :reviews, :images)
        .all
    }
  end
end
```

## With Sorting
Add sorting capabilities.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  schema do
    optional(:sort_by).maybe(:string, included_in?: %w[name price created_at])
    optional(:sort_direction).maybe(:string, included_in?: %w[asc desc])
  end

  search_with do
    scope = model_class.all

    if params[:sort_by]
      direction = params[:sort_direction] || 'asc'
      scope = scope.order("#{params[:sort_by]} #{direction}")
    end

    { items: scope }
  end
end
```

## With Metadata
Add useful metadata to the response.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  search_with do
    { items: model_class.all }
  end

  process_with do |data|
    {
      items: data[:items],
      metadata: {
        total: data[:items].count,
        categories: Category.count
      }
    }
  end
end

# Result includes metadata
# result[:metadata] => { total: 42, categories: 5 }
```

## User-Scoped List
Filter by current user automatically.

```ruby
class Order::MyOrdersService < BetterService::IndexService
  model_class Order
  cache_contexts :user_orders

  schema do
    optional(:status).maybe(:string)
  end

  search_with do
    scope = user.orders
    scope = scope.where(status: params[:status]) if params[:status]
    { items: scope.order(created_at: :desc) }
  end
end
```

## With Authorization
Restrict access to authorized users.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  authorize_with do
    user.admin? || user.has_permission?(:view_products)
  end

  search_with do
    { items: model_class.all }
  end
end
```

## With Pagination
Integrate with Kaminari or Pagy for pagination.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  schema do
    optional(:page).filled(:integer, gteq?: 1)
    optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
  end

  search_with do
    {
      items: model_class
        .page(params[:page] || 1)
        .per(params[:per_page] || 25)
    }
  end

  process_with do |data|
    items = data[:items]
    {
      items: items,
      pagination: {
        current_page: items.current_page,
        total_pages: items.total_pages,
        total_count: items.total_count,
        per_page: items.limit_value
      }
    }
  end
end
```

## Complex Multi-Field Sorting
Sort by multiple fields with nulls handling.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  schema do
    optional(:sort).maybe(:array)
  end

  search_with do
    scope = model_class.all

    # Example params[:sort]: ['price:desc', 'name:asc']
    if params[:sort]
      params[:sort].each do |sort_field|
        field, direction = sort_field.split(':')
        direction = direction&.downcase == 'desc' ? 'DESC NULLS LAST' : 'ASC NULLS FIRST'
        scope = scope.order(Arel.sql("#{field} #{direction}"))
      end
    else
      scope = scope.order(created_at: :desc)
    end

    { items: scope }
  end
end
```

## Faceted Search with Counts
Provide filter counts for faceted navigation.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  schema do
    optional(:category_id).maybe(:integer)
    optional(:status).maybe(:string)
  end

  search_with do
    scope = model_class.all
    scope = scope.where(category_id: params[:category_id]) if params[:category_id]
    scope = scope.where(status: params[:status]) if params[:status]
    { items: scope }
  end

  process_with do |data|
    {
      items: data[:items],
      facets: {
        categories: model_class.group(:category_id).count,
        statuses: model_class.group(:status).count,
        price_ranges: {
          'under_50': model_class.where('price < ?', 50).count,
          '50_to_100': model_class.where(price: 50..100).count,
          'over_100': model_class.where('price > ?', 100).count
        }
      }
    }
  end
end
```

## Scopes Composition
Combine named scopes for complex queries.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  schema do
    optional(:featured).maybe(:bool)
    optional(:on_sale).maybe(:bool)
    optional(:in_stock).maybe(:bool)
  end

  search_with do
    scope = model_class.all

    # Use model scopes
    scope = scope.featured if params[:featured]
    scope = scope.on_sale if params[:on_sale]
    scope = scope.in_stock if params[:in_stock]

    { items: scope.order(position: :asc) }
  end
end

# In Product model:
# scope :featured, -> { where(featured: true) }
# scope :on_sale, -> { where('discount_percentage > ?', 0) }
# scope :in_stock, -> { where('stock_quantity > ?', 0) }
```

## Performance Optimization with Select
Optimize for large datasets by selecting only needed fields.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  schema do
    optional(:fields).maybe(:array)
  end

  search_with do
    # Default fields for listing
    fields = params[:fields] || %w[id name price category_id]

    {
      items: model_class
        .select(fields)
        .includes(:category)
        .limit(1000)
    }
  end

  respond_with do |data|
    {
      items: data[:items].map { |item|
        {
          id: item.id,
          name: item.name,
          price: item.price.to_f,
          category: item.category&.name
        }
      }
    }
  end
end
```
