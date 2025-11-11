# Instrumentation Events

Examples of all events published by BetterService and their payloads.

## service.started Event

Published when service execution begins, before any service logic runs.

```ruby
# Subscribe to started events
events = []
ActiveSupport::Notifications.subscribe("service.started") do |name, start, finish, id, payload|
  events << payload
end

# Execute service
Product::CreateService.new(user, params: { name: "Widget", price: 100 }).call

# Inspect payload
payload = events.first
# => {
#   service_name: "Product::CreateService",
#   user_id: 123,
#   timestamp: "2025-11-11T10:30:00Z",
#   params: { name: "Widget", price: 100 }  # if include_args enabled
# }
```

## service.completed Event

Published when service completes successfully with result.

```ruby
# Subscribe to completed events
completed_events = []
ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
  completed_events << payload
end

# Execute service
result = Product::CreateService.new(user, params: { name: "Widget", price: 100 }).call

# Inspect payload
payload = completed_events.first
# => {
#   service_name: "Product::CreateService",
#   user_id: 123,
#   duration: 45.23,              # milliseconds
#   timestamp: "2025-11-11T10:30:00Z",
#   success: true,
#   params: { name: "Widget", price: 100 },  # if include_args enabled
#   result: { success: true, resource: ... }, # if include_result enabled
#   cache_hit: false              # if service uses cache
# }

# Use duration for performance monitoring
if payload[:duration] > 1000
  puts "WARNING: Slow service detected!"
end
```

## service.failed Event

Published when service raises any exception during execution.

```ruby
# Subscribe to failed events
failed_events = []
ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
  failed_events << payload
end

# Execute service that will fail
begin
  Product::CreateService.new(user, params: { name: "", price: -10 }).call
rescue BetterService::Errors::Runtime::DatabaseError
  # Error is caught, but event was already published
end

# Inspect payload
payload = failed_events.first
# => {
#   service_name: "Product::CreateService",
#   user_id: 123,
#   duration: 12.45,
#   timestamp: "2025-11-11T10:30:00Z",
#   success: false,
#   error_class: "ActiveRecord::RecordInvalid",
#   error_message: "Validation failed: Name can't be blank",
#   error_backtrace: [
#     "app/services/product/create_service.rb:10",
#     "app/controllers/products_controller.rb:25",
#     ...
#   ],  # First 5 lines
#   params: { name: "", price: -10 }
# }

# Track error types
error_counts = failed_events.group_by { |e| e[:error_class] }.transform_values(&:count)
# => { "ActiveRecord::RecordInvalid" => 3, "ActiveRecord::RecordNotFound" => 1 }
```

## cache.hit Event

Published when cache lookup succeeds and cached result is returned.

```ruby
class Product::IndexService < BetterService::IndexService
  cache_key "products"
  cache_ttl 15.minutes

  search_with do
    user.products.all
  end
end

# Subscribe to cache hit events
cache_hits = []
ActiveSupport::Notifications.subscribe("cache.hit") do |name, start, finish, id, payload|
  cache_hits << payload
end

# First call - no cache hit
Product::IndexService.new(user, params: {}).call
# => cache_hits == []

# Second call - cache hit!
Product::IndexService.new(user, params: {}).call

# Inspect payload
payload = cache_hits.first
# => {
#   service_name: "Product::IndexService",
#   event_type: "cache_hit",
#   cache_key: "products:user_123:d41d8cd98f00b204e9800998ecf8427e",
#   context: nil,
#   timestamp: "2025-11-11T10:30:01Z"
# }
```

## cache.miss Event

Published when cache lookup fails and service executes fresh.

```ruby
class Product::IndexService < BetterService::IndexService
  cache_key "products"
  cache_ttl 15.minutes
  cache_contexts :products

  search_with do
    user.products.all
  end
end

# Subscribe to cache miss events
cache_misses = []
ActiveSupport::Notifications.subscribe("cache.miss") do |name, start, finish, id, payload|
  cache_misses << payload
end

# Clear cache to force miss
Rails.cache.clear

# Call service - cache miss
Product::IndexService.new(user, params: {}).call

# Inspect payload
payload = cache_misses.first
# => {
#   service_name: "Product::IndexService",
#   event_type: "cache_miss",
#   cache_key: "products:user_123:d41d8cd98f00b204e9800998ecf8427e",
#   context: "products",
#   timestamp: "2025-11-11T10:30:00Z"
# }
```

## Multiple Events in Sequence

Track the complete lifecycle of a service call.

```ruby
# Subscribe to all events
all_events = []

ActiveSupport::Notifications.subscribe(/^(service|cache)\./) do |name, start, finish, id, payload|
  all_events << { event: name, payload: payload }
end

# Execute cached service
Product::IndexService.new(user, params: {}).call

# Inspect event sequence
all_events.map { |e| e[:event] }
# => [
#   "service.started",
#   "cache.miss",
#   "service.completed"
# ]

# Second call with cache
Product::IndexService.new(user, params: {}).call

all_events.map { |e| e[:event] }
# => [
#   "service.started",
#   "cache.miss",
#   "service.completed",
#   "service.started",     # Second call
#   "cache.hit",           # Cache hit this time
#   "service.completed"
# ]
```

## Filtering Events by Service

Subscribe to events for specific services only.

```ruby
# Track only critical services
CRITICAL_SERVICES = ["Payment::ProcessService", "Order::CreateService"]

ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
  service_name = payload[:service_name]

  if CRITICAL_SERVICES.include?(service_name)
    CriticalServiceMonitor.track(
      service: service_name,
      duration: payload[:duration],
      success: payload[:success]
    )
  end
end
```

## Event Timing Information

Use start and finish times for precise measurements.

```ruby
ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
  # ActiveSupport provides start and finish as Time objects
  execution_time = (finish - start) * 1000  # Convert to milliseconds

  # Payload also includes duration for convenience
  duration_from_payload = payload[:duration]

  # Both should be approximately equal
  puts "Execution time: #{execution_time}ms"
  puts "Duration from payload: #{duration_from_payload}ms"
end
```

## Conditional Event Publishing

Events are only published when instrumentation is enabled.

```ruby
# Disable instrumentation
BetterService.configure do |config|
  config.instrumentation_enabled = false
end

events = []
ActiveSupport::Notifications.subscribe("service.completed") do |*args|
  events << args[4]
end

# Execute service
Product::CreateService.new(user, params: { name: "Widget", price: 100 }).call

# No events published
events.empty?  # => true

# Re-enable instrumentation
BetterService.configure do |config|
  config.instrumentation_enabled = true
end

# Execute service again
Product::CreateService.new(user, params: { name: "Widget", price: 100 }).call

# Events published
events.size  # => 1
```

## Event Payload with Nil User

Handle services called without a user.

```ruby
class Global::StatsService < BetterService::ActionService
  self._allow_nil_user = true

  schema do
    # No params required
  end

  process_with do
    { total_products: Product.count, total_users: User.count }
  end
end

# Subscribe to events
ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
  user_id = payload[:user_id]  # Will be nil

  if user_id.nil?
    puts "Global service executed (no user context)"
  else
    puts "Service executed by user #{user_id}"
  end
end

# Execute service without user
Global::StatsService.new(nil, params: {}).call
# => Prints: "Global service executed (no user context)"
```
