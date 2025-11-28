# Repository Pattern Overview

## What is the Repository Pattern?

The Repository Pattern provides an abstraction layer between your business logic (services) and data access (ActiveRecord models). It encapsulates all data access logic in dedicated repository classes.

## Why Use Repositories?

### Without Repository (Anti-Pattern)

```ruby
class Products::IndexService < BetterService::Services::IndexService
  search_with do
    # Direct ActiveRecord calls scattered in service
    products = Product.where(published: true)
                      .includes(:category)
                      .order(created_at: :desc)
                      .page(params[:page])
                      .per(20)
    { items: products }
  end
end
```

**Problems:**
- Data access logic mixed with business logic
- Hard to test (requires database)
- Duplicate queries across services
- Difficult to change data access strategy

### With Repository (Recommended)

```ruby
class Products::IndexService < BetterService::Services::IndexService
  include BetterService::Concerns::Serviceable::RepositoryAware
  repository :product

  search_with do
    { items: product_repository.published.to_a }
  end
end
```

**Benefits:**
- Clean separation of concerns
- Easy to test with mocks
- Reusable query methods
- Single place to change data access

## Key Concepts

### 1. BaseRepository

The foundation class providing standard CRUD operations:

```ruby
class ProductRepository < BetterService::Repository::BaseRepository
  def initialize
    super(Product)
  end
end
```

### 2. RepositoryAware Concern

DSL for declaring repository dependencies in services:

```ruby
class MyService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product
  repository :user, class_name: "Users::UserRepository"
  repository :booking, as: :bookings
end
```

### 3. Custom Query Methods

Domain-specific queries encapsulated in repository:

```ruby
class ProductRepository < BetterService::Repository::BaseRepository
  def published
    model.published
  end

  def by_category(category_id)
    where(category_id: category_id)
  end

  def recent(limit = 10)
    model.order(created_at: :desc).limit(limit)
  end
end
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                      Controller                          │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                       Service                            │
│  ┌─────────────────────────────────────────────────┐   │
│  │  include RepositoryAware                         │   │
│  │  repository :product                             │   │
│  │                                                  │   │
│  │  search_with do                                  │   │
│  │    { items: product_repository.published }       │   │
│  │  end                                             │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                     Repository                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │  class ProductRepository < BaseRepository        │   │
│  │    def published                                 │   │
│  │      model.published                             │   │
│  │    end                                           │   │
│  │  end                                             │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                   ActiveRecord Model                     │
│  ┌─────────────────────────────────────────────────┐   │
│  │  class Product < ApplicationRecord               │   │
│  │    scope :published, -> { where(published: true) }│   │
│  │  end                                             │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## When to Use Repositories

### Use Repositories When:

- Building services that need database access
- You want to test services without database
- Multiple services share the same queries
- You need to abstract data access patterns

### Skip Repositories When:

- Simple one-off scripts
- Direct model access in rake tasks
- Rails console exploration
- Very simple CRUD with no custom logic

## File Structure

```
app/
├── repositories/
│   ├── application_repository.rb  # Optional base class
│   ├── product_repository.rb
│   ├── user_repository.rb
│   └── booking_repository.rb
├── services/
│   └── products/
│       ├── index_service.rb
│       └── create_service.rb
└── models/
    ├── product.rb
    └── user.rb
```

## Next Steps

- [BaseRepository Methods](./02-base-repository-examples.md) - All available CRUD and query methods
- [RepositoryAware DSL](./03-repository-aware-examples.md) - Using repositories in services
- [Custom Repositories](./04-custom-repository-examples.md) - Building domain-specific repositories
