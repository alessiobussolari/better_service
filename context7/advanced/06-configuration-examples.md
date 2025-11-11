# Configuration Examples

Examples of configuring instrumentation for different scenarios.

## Default Configuration

Basic setup with all features enabled.

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  # Master switch - enable instrumentation
  config.instrumentation_enabled = true  # default: true

  # Include service params in event payloads
  config.instrumentation_include_args = true  # default: true

  # Include service results in completed events
  config.instrumentation_include_result = false  # default: false

  # No services excluded by default
  config.instrumentation_excluded_services = []  # default: []

  # Enable built-in subscribers
  config.stats_subscriber_enabled = true   # default: true
  config.log_subscriber_enabled = true     # default: true
end
```

## Production Configuration

Optimized configuration for production with privacy controls.

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  # Enable instrumentation
  config.instrumentation_enabled = true

  # Disable params to avoid leaking sensitive data
  config.instrumentation_include_args = false

  # Disable results to reduce payload size
  config.instrumentation_include_result = false

  # Exclude sensitive services from instrumentation
  config.instrumentation_excluded_services = [
    "Authentication::LoginService",
    "Authentication::LogoutService",
    "User::ChangePasswordService",
    "Payment::ProcessCreditCardService",
    "Billing::CreateInvoiceService"
  ]

  # Enable StatsSubscriber for metrics
  config.stats_subscriber_enabled = true

  # Disable LogSubscriber (use external logging instead)
  config.log_subscriber_enabled = false
end
```

## Development Configuration

Verbose configuration for development and debugging.

```ruby
# config/environments/development.rb
BetterService.configure do |config|
  # Enable all instrumentation
  config.instrumentation_enabled = true

  # Include full details for debugging
  config.instrumentation_include_args = true
  config.instrumentation_include_result = true

  # Don't exclude any services in development
  config.instrumentation_excluded_services = []

  # Enable all subscribers
  config.stats_subscriber_enabled = true
  config.log_subscriber_enabled = true
end

# Set verbose log level
Rails.logger.level = :debug
```

## Test Configuration

Minimal configuration for fast test execution.

```ruby
# config/environments/test.rb
BetterService.configure do |config|
  # Disable instrumentation in tests for speed
  config.instrumentation_enabled = false

  # Disable subscribers
  config.stats_subscriber_enabled = false
  config.log_subscriber_enabled = false
end

# Optionally enable for specific tests
RSpec.configure do |config|
  config.before(:each, instrumentation: true) do
    BetterService.configure do |c|
      c.instrumentation_enabled = true
    end
  end

  config.after(:each, instrumentation: true) do
    BetterService.configure do |c|
      c.instrumentation_enabled = false
    end
  end
end

# Use in specific tests
RSpec.describe Product::CreateService, instrumentation: true do
  it "publishes service.completed event" do
    events = []
    ActiveSupport::Notifications.subscribe("service.completed") { |*args| events << args[4] }

    service.call

    expect(events.size).to eq(1)
  end
end
```

## Staging Configuration

Balance between production security and debugging capability.

```ruby
# config/environments/staging.rb
BetterService.configure do |config|
  # Enable instrumentation
  config.instrumentation_enabled = true

  # Include params for debugging (staging is not production)
  config.instrumentation_include_args = true

  # Disable results to reduce payload
  config.instrumentation_include_result = false

  # Exclude only the most sensitive services
  config.instrumentation_excluded_services = [
    "Payment::ProcessCreditCardService"
  ]

  # Enable both subscribers
  config.stats_subscriber_enabled = true
  config.log_subscriber_enabled = true
end
```

## Environment-Specific Configuration

Different configuration per environment using environment variables.

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  # Enable/disable via environment variable
  config.instrumentation_enabled = ENV.fetch('BETTER_SERVICE_INSTRUMENTATION', 'true') == 'true'

  # Control params inclusion via environment
  config.instrumentation_include_args = ENV.fetch('BETTER_SERVICE_INCLUDE_ARGS', 'true') == 'true'

  # Control result inclusion
  config.instrumentation_include_result = ENV.fetch('BETTER_SERVICE_INCLUDE_RESULT', 'false') == 'true'

  # Load excluded services from environment (comma-separated)
  excluded_services = ENV.fetch('BETTER_SERVICE_EXCLUDED', '').split(',').map(&:strip)
  config.instrumentation_excluded_services = excluded_services

  # Control subscribers via environment
  config.stats_subscriber_enabled = ENV.fetch('BETTER_SERVICE_STATS', 'true') == 'true'
  config.log_subscriber_enabled = ENV.fetch('BETTER_SERVICE_LOGS', 'true') == 'true'
end

# .env.production
# BETTER_SERVICE_INSTRUMENTATION=true
# BETTER_SERVICE_INCLUDE_ARGS=false
# BETTER_SERVICE_INCLUDE_RESULT=false
# BETTER_SERVICE_EXCLUDED=Authentication::LoginService,Payment::ProcessService
# BETTER_SERVICE_STATS=true
# BETTER_SERVICE_LOGS=false

# .env.development
# BETTER_SERVICE_INSTRUMENTATION=true
# BETTER_SERVICE_INCLUDE_ARGS=true
# BETTER_SERVICE_INCLUDE_RESULT=true
# BETTER_SERVICE_EXCLUDED=
# BETTER_SERVICE_STATS=true
# BETTER_SERVICE_LOGS=true
```

## Exclude High-Frequency Services

Reduce overhead by excluding services called frequently.

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  config.instrumentation_enabled = true

  # Exclude services that are called very frequently
  config.instrumentation_excluded_services = [
    "HealthCheck::PingService",       # Called every 10 seconds
    "Session::RefreshService",        # Called on every request
    "Cache::WarmupService",           # Background job running constantly
    "Internal::MetricsService",       # Self-monitoring service
    "RateLimit::CheckService"         # Called before every API request
  ]

  config.stats_subscriber_enabled = true
  config.log_subscriber_enabled = true
end
```

## Include Results for Debugging

Enable result inclusion temporarily for debugging specific issues.

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  config.instrumentation_enabled = true
  config.instrumentation_include_args = true

  # Enable result inclusion only in development and staging
  config.instrumentation_include_result = !Rails.env.production?

  config.stats_subscriber_enabled = true
  config.log_subscriber_enabled = true
end

# Or control via feature flag
BetterService.configure do |config|
  config.instrumentation_include_result = FeatureFlags.enabled?(:debug_service_results)
end

# Enable temporarily in Rails console (production)
BetterService.configure do |config|
  config.instrumentation_include_result = true
end

# Run debugging...

# Disable after debugging
BetterService.configure do |config|
  config.instrumentation_include_result = false
end
```

## Disable Instrumentation for Specific Request

Disable instrumentation for specific scenarios at runtime.

```ruby
# In controller or middleware
class ApiController < ApplicationController
  around_action :disable_instrumentation_for_webhooks, only: [:webhook]

  private

  def disable_instrumentation_for_webhooks
    original_setting = BetterService.configuration.instrumentation_enabled

    # Disable instrumentation for webhook processing
    BetterService.configure { |c| c.instrumentation_enabled = false }

    yield

    # Restore original setting
    BetterService.configure { |c| c.instrumentation_enabled = original_setting }
  end
end

# Webhook endpoint won't publish instrumentation events
```

## Conditional Subscriber Enabling

Enable subscribers based on environment or feature flags.

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  config.instrumentation_enabled = true
  config.instrumentation_include_args = true
  config.instrumentation_include_result = false
  config.instrumentation_excluded_services = []

  # Enable StatsSubscriber always
  config.stats_subscriber_enabled = true

  # Enable LogSubscriber only in development and test
  config.log_subscriber_enabled = Rails.env.development? || Rails.env.test?

  # Or use feature flags
  # config.log_subscriber_enabled = FeatureFlags.enabled?(:service_logging)
end
```

## Multi-Tenant Configuration

Different configuration per tenant.

```ruby
# config/initializers/better_service.rb

# Default configuration
BetterService.configure do |config|
  config.instrumentation_enabled = true
  config.instrumentation_include_args = false
  config.instrumentation_include_result = false
  config.instrumentation_excluded_services = []
  config.stats_subscriber_enabled = true
  config.log_subscriber_enabled = false
end

# Per-tenant configuration
class TenantAwareInstrumentation
  def self.configure_for_tenant(tenant)
    case tenant.plan
    when 'enterprise'
      # Enterprise customers get full instrumentation
      BetterService.configure do |config|
        config.instrumentation_enabled = true
        config.instrumentation_include_args = true
      end
    when 'premium'
      # Premium customers get basic instrumentation
      BetterService.configure do |config|
        config.instrumentation_enabled = true
        config.instrumentation_include_args = false
      end
    else
      # Free tier - no instrumentation
      BetterService.configure do |config|
        config.instrumentation_enabled = false
      end
    end
  end
end

# In controller or middleware
around_action :configure_instrumentation_for_tenant

def configure_instrumentation_for_tenant
  TenantAwareInstrumentation.configure_for_tenant(current_tenant)
  yield
end
```

## Gradual Rollout Configuration

Gradually enable instrumentation using percentage rollout.

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  # Enable for percentage of users/requests
  rollout_percentage = ENV.fetch('INSTRUMENTATION_ROLLOUT_PERCENT', '100').to_i

  config.instrumentation_enabled = (rand(100) < rollout_percentage)

  config.instrumentation_include_args = true
  config.instrumentation_include_result = false
  config.instrumentation_excluded_services = []
  config.stats_subscriber_enabled = true
  config.log_subscriber_enabled = true
end

# Start with 10%, gradually increase
# INSTRUMENTATION_ROLLOUT_PERCENT=10  # First week
# INSTRUMENTATION_ROLLOUT_PERCENT=25  # Second week
# INSTRUMENTATION_ROLLOUT_PERCENT=50  # Third week
# INSTRUMENTATION_ROLLOUT_PERCENT=100 # Full rollout
```

## Reset Configuration

Reset configuration to defaults at runtime.

```ruby
# In Rails console or rake task

# Save current configuration
original_config = {
  enabled: BetterService.configuration.instrumentation_enabled,
  include_args: BetterService.configuration.instrumentation_include_args,
  include_result: BetterService.configuration.instrumentation_include_result,
  excluded: BetterService.configuration.instrumentation_excluded_services.dup
}

# Change configuration for testing
BetterService.configure do |config|
  config.instrumentation_enabled = true
  config.instrumentation_include_args = true
  config.instrumentation_include_result = true
  config.instrumentation_excluded_services = []
end

# Run tests...

# Restore original configuration
BetterService.configure do |config|
  config.instrumentation_enabled = original_config[:enabled]
  config.instrumentation_include_args = original_config[:include_args]
  config.instrumentation_include_result = original_config[:include_result]
  config.instrumentation_excluded_services = original_config[:excluded]
end

# Or reset to defaults
BetterService.reset_configuration!
```

## Validation of Configuration

Validate configuration on startup.

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  config.instrumentation_enabled = true
  config.instrumentation_include_args = ENV['RAILS_ENV'] != 'production'
  config.instrumentation_include_result = false

  # Validate excluded services exist
  excluded_services = ENV.fetch('BETTER_SERVICE_EXCLUDED', '').split(',').map(&:strip)

  # Warn if excluding non-existent services
  excluded_services.each do |service_name|
    begin
      service_name.constantize
    rescue NameError
      Rails.logger.warn "[BetterService] Warning: Excluding non-existent service '#{service_name}'"
    end
  end

  config.instrumentation_excluded_services = excluded_services
  config.stats_subscriber_enabled = true
  config.log_subscriber_enabled = true
end

# Verify configuration is valid
if BetterService.configuration.instrumentation_enabled
  Rails.logger.info "[BetterService] Instrumentation enabled"
  Rails.logger.info "[BetterService] Including args: #{BetterService.configuration.instrumentation_include_args}"
  Rails.logger.info "[BetterService] Including result: #{BetterService.configuration.instrumentation_include_result}"
  Rails.logger.info "[BetterService] Excluded services: #{BetterService.configuration.instrumentation_excluded_services.join(', ')}"
else
  Rails.logger.info "[BetterService] Instrumentation disabled"
end
```
