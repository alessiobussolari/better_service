# LogSubscriber Examples

Examples of using the built-in LogSubscriber for automatic service logging.

## Basic Logging

Automatic logging of service lifecycle events.

```ruby
# Enable LogSubscriber in initializer
BetterService.configure do |config|
  config.log_subscriber_enabled = true
end

# Execute service
Product::CreateService.new(user, params: { name: "Widget", price: 100 }).call

# Logs written automatically to Rails.logger:
# I, [2025-11-11T10:30:00.123]  INFO -- : [BetterService] Product::CreateService started (user: 123)
# I, [2025-11-11T10:30:00.168]  INFO -- : [BetterService] Product::CreateService completed in 45.2ms (user: 123)
```

## Error Logging

Automatic logging of service failures with error details.

```ruby
# Execute service that will fail
begin
  Product::CreateService.new(user, params: { name: "", price: -10 }).call
rescue BetterService::Errors::Runtime::DatabaseError
  # Caught
end

# Logs written automatically:
# I, [2025-11-11T10:30:00.123]  INFO -- : [BetterService] Product::CreateService started (user: 123)
# E, [2025-11-11T10:30:00.135]  ERROR -- : [BetterService] ERROR: Product::CreateService failed in 12.4ms (user: 123)
# E, [2025-11-11T10:30:00.135]  ERROR -- : Error: ActiveRecord::RecordInvalid - Validation failed: Name can't be blank
```

## Cache Event Logging

Log cache hits and misses at DEBUG level.

```ruby
class Product::IndexService < BetterService::IndexService
  cache_key "products"
  cache_ttl 15.minutes

  search_with do
    user.products.all
  end
end

# Set log level to DEBUG to see cache events
Rails.logger.level = :debug

# First call - cache miss
Product::IndexService.new(user, params: {}).call
# Logs:
# I, [...]  INFO -- : [BetterService] Product::IndexService started (user: 123)
# D, [...] DEBUG -- : [BetterService] Cache MISS for Product::IndexService (key: products:user_123:...)
# I, [...]  INFO -- : [BetterService] Product::IndexService completed in 120.5ms (user: 123)

# Second call - cache hit
Product::IndexService.new(user, params: {}).call
# Logs:
# I, [...]  INFO -- : [BetterService] Product::IndexService started (user: 123)
# D, [...] DEBUG -- : [BetterService] Cache HIT for Product::IndexService (key: products:user_123:...)
# I, [...]  INFO -- : [BetterService] Product::IndexService completed in 2.3ms (user: 123)
```

## Log Levels Configuration

Control which events are logged by adjusting Rails log level.

```ruby
# Production: Only INFO and ERROR
Rails.logger.level = :info

# Logs service start/complete (INFO) and failures (ERROR)
# Does NOT log cache hits/misses (DEBUG)

# Development: All events including cache
Rails.logger.level = :debug

# Logs everything: service lifecycle, cache events, debug info

# Testing: Suppress logging
Rails.logger.level = :error

# Only logs service failures, suppresses routine logs
```

## Disable LogSubscriber

Disable automatic logging when not needed.

```ruby
# In initializer or specific environment
BetterService.configure do |config|
  config.log_subscriber_enabled = false
end

# Execute service
Product::CreateService.new(user, params: { name: "Widget", price: 100 }).call

# No automatic logs written
# Manual logging still works as usual
```

## Log Format Customization

LogSubscriber uses standard Rails.logger - customize via Rails configuration.

```ruby
# config/environments/development.rb
config.log_formatter = Logger::Formatter.new

# config/environments/production.rb
config.log_formatter = ::Logger::Formatter.new
config.log_tags = [:request_id]

# With tagged logging
Rails.application.config.log_tags = [:uuid, :remote_ip]

# Logs now include tags:
# [abc-123] [192.168.1.1] [BetterService] Product::CreateService started (user: 123)
```

## Structured Logging

Use JSON formatter for structured logs in production.

```ruby
# Gemfile
gem 'lograge'

# config/environments/production.rb
config.lograge.enabled = true
config.lograge.formatter = Lograge::Formatters::Json.new

# BetterService logs integrate with structured logging:
# {
#   "timestamp": "2025-11-11T10:30:00.123Z",
#   "level": "INFO",
#   "message": "[BetterService] Product::CreateService completed in 45.2ms (user: 123)",
#   "service": "Product::CreateService",
#   "duration": 45.2,
#   "user_id": 123
# }
```

## Separate Log File for Services

Route BetterService logs to dedicated file.

```ruby
# config/initializers/better_service.rb

# Create separate logger for services
service_logger = Logger.new("#{Rails.root}/log/services.log")
service_logger.formatter = Logger::Formatter.new

# Disable default LogSubscriber
BetterService.configure do |config|
  config.log_subscriber_enabled = false
end

# Create custom subscriber with separate logger
class CustomServiceLogger
  def self.attach
    logger = Logger.new("#{Rails.root}/log/services.log")

    ActiveSupport::Notifications.subscribe("service.started") do |name, start, finish, id, payload|
      logger.info "[START] #{payload[:service_name]} (user: #{payload[:user_id]})"
    end

    ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
      logger.info "[COMPLETE] #{payload[:service_name]} in #{payload[:duration]}ms (user: #{payload[:user_id]})"
    end

    ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
      logger.error "[FAILED] #{payload[:service_name]} in #{payload[:duration]}ms (user: #{payload[:user_id]})"
      logger.error "Error: #{payload[:error_class]} - #{payload[:error_message]}"
    end
  end
end

CustomServiceLogger.attach
```

## Conditional Logging

Log only specific services or conditions.

```ruby
# Disable default LogSubscriber
BetterService.configure do |config|
  config.log_subscriber_enabled = false
end

# Custom subscriber that logs only slow services
class SlowServiceLogger
  SLOW_THRESHOLD = 1000 # milliseconds

  def self.attach
    ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
      duration = payload[:duration]
      service_name = payload[:service_name]

      if duration > SLOW_THRESHOLD
        Rails.logger.warn "[SLOW] #{service_name} took #{duration}ms (threshold: #{SLOW_THRESHOLD}ms)"
        Rails.logger.warn "User: #{payload[:user_id]}, Params: #{payload[:params]}"
      end
    end
  end
end

SlowServiceLogger.attach
```

## Request Correlation

Correlate service logs with HTTP requests using request IDs.

```ruby
# In ApplicationController
class ApplicationController < ActionController::Base
  around_action :log_with_request_id

  private

  def log_with_request_id
    request_id = request.uuid

    Rails.logger.tagged(request_id) do
      # Disable default LogSubscriber
      BetterService.configure { |c| c.log_subscriber_enabled = false }

      # Custom logging with request ID
      ActiveSupport::Notifications.subscribe(/^service\./) do |name, start, finish, id, payload|
        event_type = name.split('.').last
        service_name = payload[:service_name]

        case event_type
        when 'started'
          Rails.logger.info "[#{request_id}] Service started: #{service_name}"
        when 'completed'
          Rails.logger.info "[#{request_id}] Service completed: #{service_name} (#{payload[:duration]}ms)"
        when 'failed'
          Rails.logger.error "[#{request_id}] Service failed: #{service_name} - #{payload[:error_message]}"
        end
      end

      yield
    end
  end
end

# Logs with request correlation:
# [abc-123-def] Service started: Product::CreateService
# [abc-123-def] Service completed: Product::CreateService (45.2ms)
# [abc-123-def] Controller action completed
```

## Performance Logging

Log detailed performance metrics for analysis.

```ruby
# Disable default LogSubscriber
BetterService.configure do |config|
  config.log_subscriber_enabled = false
end

# Custom performance logger
class PerformanceLogger
  def self.attach
    ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
      service_name = payload[:service_name]
      duration = payload[:duration]
      user_id = payload[:user_id]

      # Log in structured format for parsing
      Rails.logger.info({
        event: 'service_completed',
        service: service_name,
        duration_ms: duration,
        user_id: user_id,
        timestamp: payload[:timestamp],
        cache_hit: payload[:cache_hit]
      }.to_json)
    end
  end
end

PerformanceLogger.attach

# Logs:
# {"event":"service_completed","service":"Product::CreateService","duration_ms":45.2,"user_id":123,"timestamp":"2025-11-11T10:30:00Z","cache_hit":false}

# Can be parsed by log aggregation tools (ELK, Splunk, etc.)
```

## Debug Logging for Development

Enhanced logging in development with more details.

```ruby
# config/environments/development.rb
if Rails.env.development?
  # Disable default LogSubscriber
  BetterService.configure { |c| c.log_subscriber_enabled = false }

  # Custom verbose logger for development
  class VerboseDevLogger
    def self.attach
      ActiveSupport::Notifications.subscribe("service.started") do |name, start, finish, id, payload|
        Rails.logger.debug "=" * 80
        Rails.logger.debug "[SERVICE START] #{payload[:service_name]}"
        Rails.logger.debug "User: #{payload[:user_id]}"
        Rails.logger.debug "Params: #{payload[:params].inspect}"
        Rails.logger.debug "-" * 80
      end

      ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
        Rails.logger.debug "[SERVICE COMPLETE] #{payload[:service_name]}"
        Rails.logger.debug "Duration: #{payload[:duration]}ms"
        Rails.logger.debug "Success: #{payload[:success]}"
        Rails.logger.debug "Result: #{payload[:result].inspect}" if payload[:result]
        Rails.logger.debug "=" * 80
      end

      ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
        Rails.logger.error "!" * 80
        Rails.logger.error "[SERVICE FAILED] #{payload[:service_name]}"
        Rails.logger.error "Duration: #{payload[:duration]}ms"
        Rails.logger.error "Error: #{payload[:error_class]}"
        Rails.logger.error "Message: #{payload[:error_message]}"
        Rails.logger.error "Backtrace:"
        payload[:error_backtrace]&.each { |line| Rails.logger.error "  #{line}" }
        Rails.logger.error "!" * 80
      end
    end
  end

  VerboseDevLogger.attach
end

# Development logs with full details:
# ================================================================================
# [SERVICE START] Product::CreateService
# User: 123
# Params: {:name=>"Widget", :price=>100}
# --------------------------------------------------------------------------------
# [SERVICE COMPLETE] Product::CreateService
# Duration: 45.2ms
# Success: true
# Result: {:success=>true, :resource=>#<Product id: 1, name: "Widget", price: 100>}
# ================================================================================
```
