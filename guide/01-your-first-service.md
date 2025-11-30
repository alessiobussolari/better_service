# Your First Service

Learn to build a service from scratch.

---

## Understanding Services

### What is a Service?

Services encapsulate business logic in a clean, testable pattern.

```ruby
# Without services: logic scattered in controllers
class ProductsController < ApplicationController
  def create
    @product = Product.new(product_params)
    @product.user = current_user
    # validation logic...
    # authorization logic...
    # business logic...
    @product.save!
  end
end

# With services: logic organized in one place
class ProductsController < ApplicationController
  def create
    result = Product::CreateService.new(current_user, params: product_params).call
    # Handle result...
  end
end
```

--------------------------------

## The 5-Phase Flow

### Execution Phases

Every service follows this flow automatically.

```ruby
# Phase 1: VALIDATION (during initialize)
# → Schema validates params
# → Raises ValidationError if invalid

# Phase 2: AUTHORIZATION (during call)
# → authorize_with block executes
# → Returns failure if unauthorized

# Phase 3: SEARCH (during call)
# → search_with block loads data
# → Prepares context for processing

# Phase 4: PROCESS (during call)
# → process_with block executes
# → Contains main business logic

# Phase 5: RESPOND (during call)
# → respond_with block formats output
# → Returns Result wrapper
```

--------------------------------

## Create Your First Service

### Step 1: Define the Service

Create a simple greeting service.

```ruby
# app/services/greeting/hello_service.rb
class Greeting::HelloService < BetterService::Services::Base
  # Phase 1: Define what params we accept
  schema do
    required(:name).filled(:string)
    optional(:formal).filled(:bool)
  end

  # Phase 4: Main logic
  process_with do
    greeting = if params[:formal]
      "Good day, #{params[:name]}."
    else
      "Hello, #{params[:name]}!"
    end

    { resource: greeting }
  end
end
```

--------------------------------

### Step 2: Use the Service

Call your service and handle the result.

```ruby
# In a controller
class GreetingsController < ApplicationController
  def show
    result = Greeting::HelloService.new(
      current_user,
      params: { name: "Alice", formal: false }
    ).call

    if result.success?
      render json: { greeting: result.resource }
    else
      render json: { error: result.message }, status: :unprocessable_entity
    end
  end
end
```

--------------------------------

### Step 3: Test the Service

Write a simple test.

```ruby
# test/services/greeting/hello_service_test.rb
require "test_helper"

class Greeting::HelloServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.new(id: 1, name: "Test")
  end

  test "returns informal greeting" do
    result = Greeting::HelloService.new(
      @user,
      params: { name: "Alice" }
    ).call

    assert result.success?
    assert_equal "Hello, Alice!", result.resource
  end

  test "returns formal greeting" do
    result = Greeting::HelloService.new(
      @user,
      params: { name: "Alice", formal: true }
    ).call

    assert result.success?
    assert_equal "Good day, Alice.", result.resource
  end
end
```

--------------------------------

## Adding Authorization

### Restrict Access

Add an authorize_with block to control who can use the service.

```ruby
class Greeting::HelloService < BetterService::Services::Base
  schema do
    required(:name).filled(:string)
  end

  # IMPORTANT: Use `next` not `return`!
  authorize_with do
    next true if user.admin?      # Admins always allowed
    user.active?                   # Others must be active
  end

  process_with do
    { resource: "Hello, #{params[:name]}!" }
  end
end
```

--------------------------------

## Adding Search Phase

### Load Data Before Processing

Use search_with to prepare data.

```ruby
class User::ShowService < BetterService::Services::Base
  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    next true if user.admin?
    params[:id] == user.id  # Can only view own profile
  end

  search_with do
    target_user = User.find(params[:id])
    { resource: target_user }
  end

  process_with do |data|
    # data[:resource] contains user from search_with
    { resource: data[:resource] }
  end
end
```

--------------------------------

## Adding Response Formatting

### Custom Response

Use respond_with for custom formatting.

```ruby
class User::ShowService < BetterService::Services::Base
  performed_action :showed

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: User.find(params[:id]) }
  end

  process_with do |data|
    { resource: data[:resource] }
  end

  respond_with do |data|
    success_result(
      "User found successfully",
      data
    )
  end
end

# Usage
result = User::ShowService.new(current_user, params: { id: 1 }).call
result.message   # => "User found successfully"
result.resource  # => User instance
result.meta      # => { action: :showed, success: true }
```

--------------------------------

## Complete Example

### Full Service with All Phases

A complete service using all phases.

```ruby
class Article::CreateService < BetterService::Services::Base
  performed_action :created
  with_transaction true

  schema do
    required(:title).filled(:string, min_size?: 3)
    required(:body).filled(:string)
    optional(:published).filled(:bool)
  end

  authorize_with do
    next true if user.admin?
    user.can_write_articles?
  end

  search_with do
    { context: { author: user } }
  end

  process_with do |data|
    article = Article.create!(
      title: params[:title],
      body: params[:body],
      published: params[:published] || false,
      author: data[:context][:author]
    )
    { resource: article }
  end

  respond_with do |data|
    success_result("Article created successfully", data)
  end
end
```

--------------------------------

## Next Steps

### Continue Learning

What to learn next.

```ruby
# Now that you understand the basics:

# 1. Learn CRUD patterns
#    → guide/02-crud-services.md

# 2. Master authorization
#    → guide/03-authorization.md

# 3. Advanced validation
#    → guide/04-validation.md
```

--------------------------------
