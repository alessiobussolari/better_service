# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-11-11

### Added

#### Core Service Types
- **6 specialized service types** for common CRUD operations:
  - `IndexService` - List/search operations with pagination, filtering, sorting
  - `ShowService` - Single resource retrieval with authorization
  - `CreateService` - Resource creation with automatic transactions
  - `UpdateService` - Resource updates with automatic transactions
  - `DestroyService` - Resource deletion with automatic transactions
  - `ActionService` - Custom operations with configurable transactions

#### 5-Phase Execution Flow
- **Validation Phase** - Automatic parameter validation with Dry::Schema
- **Authorization Phase** - Built-in authorization checks with `authorize_with` DSL
- **Search Phase** - Data loading with `search_with` DSL
- **Process Phase** - Business logic execution with `process_with` DSL
- **Respond Phase** - Response formatting with `respond_with` DSL and presenters

#### Schema Validation
- Integration with `dry-schema` gem for parameter validation
- DSL for defining schema rules with required/optional fields
- Type validations (string, integer, hash, array, etc.)
- Custom validation rules with `rule(:field)` blocks
- Comprehensive validation error messages

#### Authorization
- Built-in authorization with `authorize_with` DSL block
- Automatic `AuthorizationError` when authorization fails
- User context available in all service phases
- Support for nil users with `allow_nil_user` configuration

#### Transaction Management
- Automatic ActiveRecord transactions for Create/Update/Destroy services
- Manual transaction control with `transactional` configuration
- Automatic rollback on any error
- Nested transaction support

#### Cache Management
- Cache key definition with `cache_key` DSL
- Configurable TTL with `cache_ttl`
- Cache contexts for automatic invalidation
- `invalidate_cache_for(user)` method for manual invalidation
- Automatic cache key generation based on params

#### Presenter Integration
- Automatic result transformation with presenters
- `presenter PresenterClass` DSL
- Support for collection and single resource presenters
- `self.present(resource)` class method contract

#### Workflow System
- Multi-service composition with automatic rollback
- Step-based DSL: `step :name, with: ServiceClass`
- Conditional execution with `if:` parameter
- Dynamic params mapping with lambdas
- Error handling per step with `on_error:` callbacks
- Context accumulation across steps
- Transaction wrapping for entire workflow
- Automatic rollback on any step failure

#### Instrumentation & Monitoring
- Built-in `ActiveSupport::Notifications` integration
- **Service lifecycle events**:
  - `service.started` - When service execution begins
  - `service.completed` - When service completes successfully
  - `service.failed` - When service raises an exception
- **Cache events**:
  - `cache.hit` - When cache lookup succeeds
  - `cache.miss` - When cache lookup requires fresh execution
- **StatsSubscriber** - Automatic metrics collection:
  - Total executions, successes, failures
  - Average duration and P95/P99 latency
  - Cache hit/miss rates
  - Error type tracking
  - `BetterService::Subscribers::StatsSubscriber.stats` API
  - `BetterService::Subscribers::StatsSubscriber.summary` for aggregates
- **LogSubscriber** - Automatic Rails.logger integration:
  - INFO level for service start/complete
  - ERROR level for failures with full error details
  - DEBUG level for cache events
  - `[BetterService]` prefix for filtering
- **Custom subscribers** - Support for custom monitoring integrations
- **Configuration options**:
  - `instrumentation_enabled` (default: true)
  - `instrumentation_include_args` (default: true)
  - `instrumentation_include_result` (default: false)
  - `instrumentation_excluded_services` for sensitive services

#### Rails Generators
- Service generators for all 6 types:
  - `rails g serviceable:index ModelName`
  - `rails g serviceable:show ModelName`
  - `rails g serviceable:create ModelName`
  - `rails g serviceable:update ModelName`
  - `rails g serviceable:destroy ModelName`
  - `rails g serviceable:action ModelName ActionName`
- Workflow generator:
  - `rails g serviceable:workflow WorkflowName`
- Scaffold generator (all 5 CRUD services):
  - `rails g serviceable:scaffold ModelName`
- Generator options:
  - `--cache` - Add caching configuration
  - `--authorize` - Add authorization block
  - `--presenter` - Add presenter integration

#### Error Handling
- Structured exception hierarchy:
  - `BetterServiceError` base class with rich error information
  - `Configuration::SchemaRequiredError` - Schema not defined
  - `Configuration::InvalidSchemaError` - Schema validation failed
  - `Configuration::NilUserError` - User required but not provided
  - `Runtime::ValidationError` - Parameter validation failed
  - `Runtime::AuthorizationError` - Authorization check failed
  - `Runtime::ExecutionError` - Service execution error
  - `Runtime::ResourceNotFoundError` - ActiveRecord::RecordNotFound
  - `Runtime::DatabaseError` - Database operation failed
  - `Workflowable::WorkflowExecutionError` - Workflow failed
  - `Workflowable::StepExecutionError` - Workflow step failed
  - `Workflowable::RollbackError` - Rollback failed
- Error codes for programmatic handling (`:validation_failed`, `:unauthorized`, etc.)
- Context information in all errors (service name, params, user)
- Original error preservation with backtrace
- `to_h` method for structured error logging

#### Configuration System
- Global configuration with `BetterService.configure` block
- Per-service configuration options:
  - `allow_nil_user` - Allow services without user context
  - `transactional` - Control transaction behavior
  - Schema, cache, presenter, authorization settings
- Environment-specific configurations
- Instrumentation configuration per environment

#### Documentation
- Comprehensive README with quick start guide
- Detailed documentation for each service type
- Workflow patterns and examples
- Error handling guide
- Generator documentation
- Best practices and anti-patterns guide
- Advanced instrumentation documentation
- Context7 micro-examples for all features
- Inline YARD documentation

### Changed
- Initial stable release (no breaking changes from 0.1.0)

### Deprecated
- None

### Removed
- None

### Fixed
- None (initial 1.0.0 release)

### Security
- Built-in protection against sensitive data leaks in instrumentation
- Excluded services list for sensitive operations
- Sanitization support for custom subscribers
- MFA required for gem publishing

## [0.1.0] - 2025-11-09

### Added
- Initial release with core functionality
- 6 service types (Index, Show, Create, Update, Destroy, Action)
- Workflow system
- Basic instrumentation
- Rails generators

---

## Migration Guide

### From 0.1.0 to 1.0.0

This is a **stable API release** with no breaking changes. All code written for 0.1.0 will work with 1.0.0.

#### New Features You Can Adopt

1. **Instrumentation** is now enabled by default:
   ```ruby
   # Access service statistics
   stats = BetterService::Subscribers::StatsSubscriber.stats
   summary = BetterService::Subscribers::StatsSubscriber.summary
   ```

2. **Enhanced error handling** with error codes:
   ```ruby
   begin
     service.call
   rescue BetterService::Errors::Runtime::ValidationError => e
     e.code  # => :validation_failed
     e.to_h  # => structured error hash
   end
   ```

3. **Improved documentation** in `/docs` and `/context7` directories

No action required to upgrade - simply update your Gemfile:
```ruby
gem 'better_service', '~> 1.0.0'
```

---

## Links

- [Homepage](https://github.com/alessiobussolari/better_service)
- [Documentation](https://github.com/alessiobussolari/better_service/tree/main/docs)
- [Issues](https://github.com/alessiobussolari/better_service/issues)
- [Releases](https://github.com/alessiobussolari/better_service/releases)
