# Instrumentation & Notifications

BetterService provides built-in instrumentation using `ActiveSupport::Notifications` to publish events during service execution. This enables monitoring, metrics collection, logging, and observability for your services.

## Table of Contents

- [Overview](#overview)
- [Published Events](#published-events)
- [Event Payloads](#event-payloads)
- [Configuration](#configuration)
- [Built-in Subscribers](#built-in-subscribers)
  - [StatsSubscriber](#statssubscriber)
  - [LogSubscriber](#logsubscriber)
- [Creating Custom Subscribers](#creating-custom-subscribers)
- [Best Practices](#best-practices)

---

## Overview

Instrumentation is automatically enabled by default and publishes events at key points during service execution:

- **Service Lifecycle**: When services start, complete, or fail
- **Cache Operations**: When cache hits or misses occur
- **Performance Metrics**: Duration, success rate, error tracking

These events can be consumed by subscribers to:
- Collect metrics and statistics
- Log service execution
- Send data to monitoring systems
- Implement custom alerting
- Debug production issues

---

## Published Events

BetterService publishes the following `ActiveSupport::Notifications` events:

### Service Lifecycle Events

| Event Name | When Published | Description |
|------------|---------------|-------------|
| `service.started` | Service execution begins | Before any service logic runs |
| `service.completed` | Service completes successfully | After service returns result |
| `service.failed` | Service raises an exception | When any error occurs during execution |

### Cache Events

| Event Name | When Published | Description |
|------------|---------------|-------------|
| `cache.hit` | Cache lookup succeeds | When cached result is found and returned |
| `cache.miss` | Cache lookup fails | When cache is empty and service executes |

---

## Event Payloads

Each event includes a payload hash with relevant information:

### `service.started` Payload

```ruby
{
  service_name: "Product::CreateService",  # Full service class name
  user_id: 123,                            # User ID (if user present)
  timestamp: "2025-11-11T10:30:00Z",       # ISO8601 timestamp
  params: { name: "Product", price: 100 }  # Optional: if include_args enabled
}
```

### `service.completed` Payload

```ruby
{
  service_name: "Product::CreateService",
  user_id: 123,
  duration: 45.23,                         # Execution time in milliseconds
  timestamp: "2025-11-11T10:30:00Z",
  success: true,
  params: { name: "Product", price: 100 }, # Optional: if include_args enabled
  result: { success: true, data: {...} },  # Optional: if include_result enabled
  cache_hit: false,                        # Optional: if service uses cache
  cache_key: "products:user_123:..."      # Optional: if service uses cache
}
```

### `service.failed` Payload

```ruby
{
  service_name: "Product::CreateService",
  user_id: 123,
  duration: 12.45,
  timestamp: "2025-11-11T10:30:00Z",
  success: false,
  error_class: "ActiveRecord::RecordInvalid",
  error_message: "Validation failed: Name can't be blank",
  error_backtrace: ["app/services/...", "..."], # First 5 lines
  params: { name: "", price: 100 }        # Optional: if include_args enabled
}
```

### `cache.hit` / `cache.miss` Payload

```ruby
{
  service_name: "Product::IndexService",
  event_type: "cache_hit",                # or "cache_miss"
  cache_key: "products:user_123:abc123",
  context: "products",                    # Optional: cache context
  timestamp: "2025-11-11T10:30:00Z"
}
```

---

## Configuration

Configure instrumentation in your initializer:

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  # Enable/disable instrumentation globally
  config.instrumentation_enabled = true  # default: true

  # Include service params in event payloads
  config.instrumentation_include_args = true  # default: true

  # Include service results in event payloads
  config.instrumentation_include_result = false  # default: false

  # Exclude specific services from instrumentation
  config.instrumentation_excluded_services = [
    "HealthCheckService",
    "Internal::MetricsService"
  ]

  # Enable built-in subscribers
  config.stats_subscriber_enabled = true   # default: true
  config.log_subscriber_enabled = true     # default: true
end
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `instrumentation_enabled` | Boolean | `true` | Master switch for all instrumentation |
| `instrumentation_include_args` | Boolean | `true` | Include `params` in event payloads |
| `instrumentation_include_result` | Boolean | `false` | Include service result in completed events |
| `instrumentation_excluded_services` | Array | `[]` | Service names to exclude from instrumentation |
| `stats_subscriber_enabled` | Boolean | `true` | Enable StatsSubscriber for metrics collection |
| `log_subscriber_enabled` | Boolean | `true` | Enable LogSubscriber for logging |

**Security Note**: Be careful when enabling `instrumentation_include_args` or `instrumentation_include_result` as they may include sensitive data (passwords, tokens, etc.). Consider excluding sensitive services or sanitizing payloads in custom subscribers.

---

## Built-in Subscribers

BetterService includes two built-in subscribers that are enabled by default:

### StatsSubscriber

**Purpose**: Collects and aggregates execution statistics for all services.

**Metrics Tracked**:
- Total executions (successes + failures)
- Success and failure counts
- Average execution duration
- Cache hit/miss counts and rate
- Error types and counts

**Usage**:

```ruby
# Access all statistics
stats = BetterService::Subscribers::StatsSubscriber.stats
# => {
#   "Product::CreateService" => {
#     executions: 150,
#     successes: 148,
#     failures: 2,
#     total_duration: 4500.0,
#     avg_duration: 30.0,
#     cache_hits: 0,
#     cache_misses: 0,
#     errors: {
#       "ActiveRecord::RecordInvalid" => 2
#     }
#   },
#   "Product::IndexService" => { ... }
# }

# Get statistics for a specific service
service_stats = BetterService::Subscribers::StatsSubscriber.stats_for("Product::CreateService")
# => { executions: 150, successes: 148, ... }

# Get aggregated summary across all services
summary = BetterService::Subscribers::StatsSubscriber.summary
# => {
#   total_services: 5,
#   total_executions: 1250,
#   total_successes: 1235,
#   total_failures: 15,
#   success_rate: 98.8,
#   avg_duration: 28.5,
#   cache_hit_rate: 75.5
# }

# Reset all statistics (useful for testing or periodic reset)
BetterService::Subscribers::StatsSubscriber.reset!
```

**Configuration**:

```ruby
BetterService.configure do |config|
  config.stats_subscriber_enabled = true
end
```

**Use Cases**:
- Dashboard metrics and reporting
- Performance monitoring
- Identifying slow services
- Tracking error rates
- Cache effectiveness analysis
- Capacity planning

---

### LogSubscriber

**Purpose**: Logs all service events to `Rails.logger` for debugging and auditing.

**Log Levels**:
- `INFO`: Service started and completed events
- `ERROR`: Service failed events
- `DEBUG`: Cache hit/miss events (if log level is DEBUG)

**Log Format**:

```
# Service started
[BetterService] Product::CreateService started (user: 123)

# Service completed successfully
[BetterService] Product::CreateService completed in 45.2ms (user: 123)

# Service failed
[BetterService] ERROR: Product::CreateService failed in 12.4ms (user: 123)
Error: ActiveRecord::RecordInvalid - Validation failed: Name can't be blank

# Cache events (DEBUG level)
[BetterService] Cache HIT for Product::IndexService (key: products:user_123:...)
[BetterService] Cache MISS for Product::IndexService (key: products:user_123:...)
```

**Configuration**:

```ruby
BetterService.configure do |config|
  config.log_subscriber_enabled = true
end

# Adjust Rails log level to see cache events
Rails.logger.level = :debug
```

**Use Cases**:
- Development debugging
- Production troubleshooting
- Audit trails
- Request tracing
- Error investigation

---

## Creating Custom Subscribers

You can create custom subscribers to implement your own instrumentation logic:

### Basic Subscriber

```ruby
# app/subscribers/custom_metrics_subscriber.rb
class CustomMetricsSubscriber
  def self.attach
    ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
      # Extract metrics
      service_name = payload[:service_name]
      duration = payload[:duration]
      success = payload[:success]

      # Send to your metrics system
      Metrics.gauge("service.duration", duration, tags: ["service:#{service_name}"])
      Metrics.increment("service.executions", tags: ["service:#{service_name}", "success:#{success}"])
    end

    ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
      # Track errors
      service_name = payload[:service_name]
      error_class = payload[:error_class]

      Metrics.increment("service.errors", tags: ["service:#{service_name}", "error:#{error_class}"])
    end
  end
end

# In initializer
CustomMetricsSubscriber.attach
```

### Advanced Subscriber with State

```ruby
# app/subscribers/performance_monitor_subscriber.rb
class PerformanceMonitorSubscriber
  SLOW_THRESHOLD = 1000 # milliseconds

  def self.attach
    @slow_services = []

    ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
      duration = payload[:duration]
      service_name = payload[:service_name]

      # Alert on slow services
      if duration > SLOW_THRESHOLD
        @slow_services << {
          service: service_name,
          duration: duration,
          timestamp: payload[:timestamp],
          user_id: payload[:user_id]
        }

        # Send alert
        AlertService.send_slow_service_alert(
          service: service_name,
          duration: duration,
          threshold: SLOW_THRESHOLD
        )
      end
    end
  end

  def self.slow_services
    @slow_services
  end

  def self.reset!
    @slow_services = []
  end
end

# In initializer
PerformanceMonitorSubscriber.attach
```

### Filtering by Service

```ruby
# Subscribe only to specific services
ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
  service_name = payload[:service_name]

  # Only track critical services
  if service_name.in?(["Payment::ProcessService", "Order::CreateService"])
    CriticalServiceMonitor.track(payload)
  end
end
```

### Using Subscription Objects

```ruby
# Store subscription for later unsubscribe
@subscription = ActiveSupport::Notifications.subscribe("service.completed") do |*args|
  # Handle event
end

# Unsubscribe later
ActiveSupport::Notifications.unsubscribe(@subscription)
```

---

## Best Practices

### 1. **Privacy and Security**

```ruby
# ❌ WRONG: May expose sensitive data
config.instrumentation_include_args = true  # Includes passwords, tokens, etc.

# ✅ CORRECT: Sanitize sensitive parameters
ActiveSupport::Notifications.subscribe("service.started") do |name, start, finish, id, payload|
  params = payload[:params]&.except(:password, :token, :credit_card)
  # Use sanitized params
end

# ✅ CORRECT: Exclude sensitive services
config.instrumentation_excluded_services = [
  "Authentication::LoginService",
  "Payment::ProcessService"
]
```

### 2. **Performance Considerations**

```ruby
# ❌ WRONG: Heavy computation in subscriber
ActiveSupport::Notifications.subscribe("service.completed") do |*args|
  payload = args[4]
  # Slow external API call blocks service execution
  ExternalAPI.send_metrics(payload)
end

# ✅ CORRECT: Use background jobs for heavy work
ActiveSupport::Notifications.subscribe("service.completed") do |*args|
  payload = args[4]
  MetricsJob.perform_later(payload)  # Non-blocking
end
```

### 3. **Error Handling in Subscribers**

```ruby
# ✅ CORRECT: Handle subscriber errors gracefully
ActiveSupport::Notifications.subscribe("service.completed") do |*args|
  begin
    payload = args[4]
    Metrics.send(payload)
  rescue => error
    # Log but don't break service execution
    Rails.logger.error("Metrics subscriber failed: #{error.message}")
  end
end
```

### 4. **Selective Instrumentation**

```ruby
# ✅ CORRECT: Exclude high-frequency, low-value services
BetterService.configure do |config|
  config.instrumentation_excluded_services = [
    "HealthCheckService",        # Called every second
    "Internal::StatusService",   # Internal monitoring
    "Cache::WarmupService"       # Background maintenance
  ]
end
```

### 5. **Structured Logging**

```ruby
# ✅ CORRECT: Use structured logging for better parsing
ActiveSupport::Notifications.subscribe("service.failed") do |*args|
  payload = args[4]

  Rails.logger.error(
    message: "Service failed",
    service: payload[:service_name],
    error: payload[:error_class],
    duration: payload[:duration],
    user_id: payload[:user_id],
    timestamp: payload[:timestamp]
  )
end
```

### 6. **Testing with Instrumentation**

```ruby
# In tests, verify events are published
test "service publishes completion event" do
  events = []

  ActiveSupport::Notifications.subscribe("service.completed") do |*args|
    events << args[4]
  end

  MyService.new(user, params: { name: "test" }).call

  assert_equal 1, events.size
  assert_equal "MyService", events.first[:service_name]
end
```

### 7. **Monitoring What Matters**

**Track**:
- ✅ Error rates and types
- ✅ P95/P99 latency (not just average)
- ✅ Cache effectiveness
- ✅ Critical business operations

**Avoid**:
- ❌ Tracking every single service call
- ❌ High-cardinality tags (user IDs, session IDs)
- ❌ Full request/response bodies

---

## Summary

BetterService's instrumentation provides:

1. **Automatic event publishing** for all service executions
2. **Built-in subscribers** for stats and logging
3. **Flexible configuration** for privacy and performance
4. **Custom subscriber support** for integration with any monitoring system
5. **Production-ready** observability out of the box

---

## See Also

For practical examples and additional patterns:

- **Micro-examples**: `/context7/advanced/` - Practical code examples for all instrumentation features
  - `01-advanced-overview.md` - Quick start guide with common patterns
  - `02-instrumentation-events.md` - All event types and payloads
  - `03-stats-subscriber-examples.md` - StatsSubscriber usage patterns
  - `04-log-subscriber-examples.md` - LogSubscriber configuration
  - `05-custom-subscribers.md` - Custom subscriber examples
  - `06-configuration-examples.md` - Environment-specific configs

- **Best practices**: `/context7/examples/03-best-practices.md` - Monitoring best practices section

- **Related documentation**:
  - Service types: `/docs/services/`
  - Workflows: `/docs/workflows/`
  - Configuration: `/docs/services/08_service_configurations.md`
