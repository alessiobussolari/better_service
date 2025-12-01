# Result Wrapper

The `BetterService::Result` wrapper provides a consistent interface for service responses.

---

## API Reference

### Core Methods

Primary methods for accessing result data.

```ruby
result = Product::CreateService.new(user, params: { name: "Widget", price: 99.99 }).call

# Core Methods
result.success?   # => true (Boolean)
result.failure?   # => false (Boolean, opposite of success?)
result.resource   # => #<Product id: 1> (main object)
result.meta       # => { action: :created, success: true }
result.message    # => "Product created successfully"

# Destructuring
result.to_a       # => [resource, meta]
resource, meta = result
```

--------------------------------

## Success Response

### Success Structure

Structure of a successful service result.

```ruby
result.success?  # => true
result.resource  # => Product object (or collection for Index)
result.meta      # => {
                 #      action: :created,
                 #      success: true,
                 #      timestamp: 2024-01-15T10:30:00Z
                 #    }
result.message   # => "Product created successfully"
```

--------------------------------

## Failure Response

### Failure Structure

Structure of a failed service result.

```ruby
result.success?  # => false
result.resource  # => nil
result.meta      # => {
                 #      success: false,
                 #      error_code: :unauthorized,
                 #      error_message: "Not authorized"
                 #    }
result.message   # => "Not authorized to perform this action"
```

--------------------------------

## Error Codes

### Error Code Reference

Error codes returned in result metadata.

```ruby
# Code                   | When Raised
# -----------------------|--------------------------------------------
# :validation_failed     | Schema validation fails (during initialize)
# :unauthorized          | authorize_with block returns false
# :resource_not_found    | ResourceNotFoundError raised
# :execution_error       | ExecutionError raised in process_with
# :database_error        | DatabaseError raised (ActiveRecord failures)
```

--------------------------------

## Destructuring

### Basic Destructuring

Get resource and meta separately using destructuring.

```ruby
# Get resource and meta separately
resource, meta = Product::ShowService.new(user, params: { id: 1 }).call

if meta[:success]
  render json: resource
else
  render json: { error: meta[:error_message] }, status: :not_found
end
```

--------------------------------

### Inline Destructuring

Use destructuring inline for concise code.

```ruby
product, meta = Product::CreateService.new(user, params: params).call
redirect_to product if meta[:success]
```

--------------------------------

## JSON API Controller

### Complete API Controller

Full controller example with proper result handling.

```ruby
class Api::V1::ProductsController < ApplicationController
  def index
    result = Product::IndexService.new(current_user, params: index_params).call

    if result.success?
      render json: {
        products: result.resource,
        meta: { total: result.resource.size }
      }
    else
      render json: { error: result.message }, status: :unprocessable_entity
    end
  end

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
      }, status: error_status(result.meta[:error_code])
    end
  rescue BetterService::Errors::Runtime::ValidationError => e
    render json: { errors: e.context[:validation_errors] }, status: :unprocessable_entity
  end

  def show
    result = Product::ShowService.new(current_user, params: { id: params[:id] }).call

    if result.success?
      render json: { product: result.resource }
    else
      render json: { error: result.message }, status: :not_found
    end
  end

  private

  def error_status(code)
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

## HTML Controller

### Controller with HTML Responses

Controller example for traditional HTML responses.

```ruby
class ProductsController < ApplicationController
  def create
    result = Product::CreateService.new(current_user, params: product_params).call

    if result.success?
      redirect_to result.resource, notice: result.message
    else
      flash.now[:error] = result.message
      @product = Product.new(product_params)
      render :new, status: :unprocessable_entity
    end
  rescue BetterService::Errors::Runtime::ValidationError => e
    @product = Product.new(product_params)
    e.context[:validation_errors].each do |field, messages|
      messages.each { |msg| @product.errors.add(field, msg) }
    end
    render :new, status: :unprocessable_entity
  end

  def update
    result = Product::UpdateService.new(current_user, params: update_params).call

    if result.success?
      redirect_to result.resource, notice: result.message
    else
      @product = Product.find(params[:id])
      flash.now[:error] = result.message
      render :edit, status: :unprocessable_entity
    end
  end
end
```

--------------------------------

## Testing with Minitest

### Testing Result Objects

Test patterns for services using Minitest.

```ruby
class ProductCreateServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:seller)
    @valid_params = { name: "Widget", price: 99.99 }
  end

  test "returns successful result" do
    result = Product::CreateService.new(@user, params: @valid_params).call

    assert result.success?
    assert_instance_of Product, result.resource
    assert_equal "Widget", result.resource.name
    assert_equal :created, result.meta[:action]
  end

  test "supports destructuring" do
    product, meta = Product::CreateService.new(@user, params: @valid_params).call

    assert_instance_of Product, product
    assert_equal :created, meta[:action]
  end

  test "returns failure for unauthorized user" do
    non_seller = users(:regular)
    result = Product::CreateService.new(non_seller, params: @valid_params).call

    refute result.success?
    assert_equal :unauthorized, result.meta[:error_code]
  end

  test "raises ValidationError for invalid params" do
    error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
      Product::CreateService.new(@user, params: { name: "", price: -10 })
    end

    assert_equal :validation_failed, error.code
    assert error.context[:validation_errors].key?(:name)
  end
end
```

--------------------------------

## Best Practices

### Always Check Success First

Check success before accessing resource.

```ruby
# CORRECT
result = service.call
if result.success?
  process(result.resource)
end

# WRONG - resource may be nil on failure
result = service.call
process(result.resource)
```

--------------------------------

### Handle Both Paths

Handle success and failure cases explicitly.

```ruby
result = service.call
if result.success?
  redirect_to result.resource
else
  case result.meta[:error_code]
  when :unauthorized
    redirect_to login_path
  when :resource_not_found
    redirect_to index_path, alert: "Not found"
  else
    render :new, alert: result.message
  end
end
```

--------------------------------

## Hash-like Interface

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

Access nested data safely using `dig`.

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

Check if a key exists in the result.

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
