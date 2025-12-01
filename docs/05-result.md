# Result Wrapper

Learn how to work with BetterService::Result objects.

---

## Result Overview

### What is Result?

All services return a `BetterService::Result` object.

```ruby
result = Product::CreateService.new(user, params: { name: "Widget", price: 99.99 }).call

# result is a BetterService::Result object
result.class  # => BetterService::Result
```

--------------------------------

## Core Methods

### Checking Success

Use `success?` to check if the service succeeded.

```ruby
result = Product::CreateService.new(user, params: params).call

if result.success?
  # Handle success
  puts "Product created: #{result.resource.name}"
else
  # Handle failure
  puts "Failed: #{result.message}"
end
```

--------------------------------

### Accessing the Resource

Use `resource` to get the main object.

```ruby
result = Product::CreateService.new(user, params: params).call

if result.success?
  product = result.resource  # => #<Product id: 1, name: "Widget">
  puts product.name
end

# For index services, resource returns the collection
result = Product::IndexService.new(user, params: {}).call
products = result.resource  # => [#<Product>, #<Product>, ...]
```

--------------------------------

### Accessing Metadata

Use `meta` to get metadata about the operation.

```ruby
result = Product::CreateService.new(user, params: params).call

result.meta[:action]   # => :created
result.meta[:success]  # => true

# On failure
result.meta[:error_code]    # => :unauthorized
result.meta[:error_message] # => "Not authorized"
```

--------------------------------

### Getting the Message

Use `message` to get a human-readable message.

```ruby
result = Product::CreateService.new(user, params: params).call

result.message  # => "Product Widget created successfully"

# On failure
result.message  # => "Not authorized to perform this action"
```

--------------------------------

## Destructuring

### Basic Destructuring

Extract resource and meta with destructuring.

```ruby
resource, meta = Product::CreateService.new(user, params: params).call

if meta[:success]
  puts "Created: #{resource.name}"
else
  puts "Error: #{meta[:error_message]}"
end
```

--------------------------------

### Inline Destructuring

Use destructuring inline.

```ruby
product, meta = Product::ShowService.new(user, params: { id: 1 }).call

redirect_to product if meta[:success]
```

--------------------------------

### to_a Method

Explicitly convert to array.

```ruby
result = Product::CreateService.new(user, params: params).call
array = result.to_a  # => [resource, meta]
```

--------------------------------

## Success Patterns

### Standard Success Response

Structure of a successful result.

```ruby
result = Product::CreateService.new(user, params: { name: "Widget", price: 99.99 }).call

result.success?   # => true
result.failure?   # => false
result.resource   # => #<Product id: 1, name: "Widget">
result.message    # => "Product created successfully"
result.meta       # => {
                  #      action: :created,
                  #      success: true,
                  #      timestamp: 2024-01-15T10:30:00Z
                  #    }
```

--------------------------------

### Index Success Response

Result from listing services.

```ruby
result = Product::IndexService.new(user, params: { page: 1 }).call

result.success?   # => true
result.resource   # => [#<Product>, #<Product>, ...] (collection)
result.meta       # => {
                  #      action: :listed,
                  #      success: true
                  #    }
```

--------------------------------

## Failure Patterns

### Authorization Failure

Result when authorization fails.

```ruby
result = Product::UpdateService.new(non_owner, params: { id: 1 }).call

result.success?           # => false
result.failure?           # => true
result.resource           # => nil
result.message            # => "Not authorized"
result.meta[:error_code]  # => :unauthorized
```

--------------------------------

### Resource Not Found

Result when resource doesn't exist.

```ruby
result = Product::ShowService.new(user, params: { id: 99999 }).call

result.success?           # => false
result.resource           # => nil
result.message            # => "Product not found"
result.meta[:error_code]  # => :resource_not_found
```

--------------------------------

## Controller Patterns

### JSON API Controller

Use results in API controllers.

```ruby
class Api::ProductsController < ApplicationController
  def create
    result = Product::CreateService.new(current_user, params: product_params).call

    if result.success?
      render json: {
        product: result.resource,
        message: result.message
      }, status: :created
    else
      render json: {
        error: result.message,
        code: result.meta[:error_code]
      }, status: error_status_for(result.meta[:error_code])
    end
  end

  private

  def error_status_for(code)
    case code
    when :unauthorized then :forbidden
    when :resource_not_found then :not_found
    when :validation_failed then :unprocessable_entity
    else :unprocessable_entity
    end
  end
end
```

--------------------------------

### HTML Controller

Use results in traditional controllers.

```ruby
class ProductsController < ApplicationController
  def create
    result = Product::CreateService.new(current_user, params: product_params).call

    if result.success?
      redirect_to result.resource, notice: result.message
    else
      @product = Product.new(product_params)
      flash.now[:error] = result.message
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    result = Product::DestroyService.new(current_user, params: { id: params[:id] }).call

    if result.success?
      redirect_to products_path, notice: result.message
    else
      redirect_to products_path, alert: result.message
    end
  end
end
```

--------------------------------

## Error Code Reference

### Available Error Codes

Error codes you may encounter.

```ruby
# Code                 | Meaning
# ---------------------|----------------------------------------
# :validation_failed   | Schema validation failed (during initialize)
# :unauthorized        | authorize_with returned false
# :resource_not_found  | ResourceNotFoundError raised
# :execution_error     | ExecutionError raised
# :database_error      | DatabaseError raised
# :transaction_error   | Transaction rollback occurred
```

--------------------------------

## Conditional Logic

### Switch on Error Code

Handle different failure types.

```ruby
result = service.call

unless result.success?
  case result.meta[:error_code]
  when :unauthorized
    redirect_to login_path, alert: "Please log in"
  when :resource_not_found
    redirect_to products_path, alert: "Product not found"
  when :validation_failed
    flash.now[:error] = "Please check your input"
    render :new
  else
    flash.now[:error] = result.message
    render :new
  end
end
```

--------------------------------

## Best Practices

### Always Check Success

Never assume success.

```ruby
# WRONG - resource might be nil
result = service.call
process(result.resource)

# CORRECT - check first
result = service.call
if result.success?
  process(result.resource)
else
  handle_error(result)
end
```

--------------------------------

### Use Meaningful Error Handling

Handle errors appropriately.

```ruby
result = Product::CreateService.new(current_user, params: params).call

if result.success?
  # Success path
  redirect_to result.resource, notice: result.message
else
  # Provide context-specific error handling
  case result.meta[:error_code]
  when :unauthorized
    redirect_to root_path, alert: "You can't create products"
  when :database_error
    @product = Product.new(params)
    @product.errors.add(:base, "Could not save to database")
    render :new
  else
    @product = Product.new(params)
    flash.now[:error] = result.message
    render :new
  end
end
```

--------------------------------

### Destructuring for Concise Code

Use destructuring when appropriate.

```ruby
# Simple case - destructuring is clean
product, meta = Product::ShowService.new(user, params: { id: id }).call
render json: product if meta[:success]

# Complex case - full result is better
result = Product::CreateService.new(user, params: params).call
if result.success?
  log_creation(result.resource, result.meta)
  send_notification(result.resource)
  redirect_to result.resource, notice: result.message
end
```

--------------------------------

## Hash-like Access

### Bracket Access `[]`

Access result data using bracket notation.

```ruby
result = Product::CreateService.new(user, params: params).call

# Direct access to core attributes
result[:resource]     # => #<Product id: 1>
result[:meta]         # => { action: :created, success: true }
result[:success]      # => true
result[:message]      # => "Product created"
result[:action]       # => :created

# Access any meta key
result[:error_code]   # => :unauthorized (on failure)
result[:custom_key]   # => value from meta[:custom_key]
```

--------------------------------

### Nested Access `dig`

Access nested data safely.

```ruby
result = service.call

# Single level
result.dig(:resource)          # => #<Product>
result.dig(:meta)              # => { action: :created, success: true }

# Nested access into meta
result.dig(:meta, :action)                      # => :created
result.dig(:validation_errors, :name)           # => ["can't be blank"]

# Safe nil handling
result.dig(:nonexistent)                        # => nil
result.dig(:meta, :missing_key)                 # => nil
```

--------------------------------

### Key Check `key?`

Check if a key exists.

```ruby
result.key?(:resource)     # => true
result.key?(:meta)         # => true
result.key?(:success)      # => true
result.key?(:action)       # => true
result.key?(:unknown)      # => false

# Alias
result.has_key?(:resource) # => true
```

--------------------------------
