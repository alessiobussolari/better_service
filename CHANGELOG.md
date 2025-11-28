# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-11-28

### Added

#### Repository Pattern
- **`BetterService::Repository::BaseRepository`** - Generic repository pattern for data access abstraction
  - Standard CRUD methods: `find`, `find_by`, `where`, `all`, `count`, `exists?`
  - Create methods: `build`, `create`, `create!`
  - Update methods: `update`, `update!`
  - Delete methods: `destroy`, `destroy!`, `delete`
  - Advanced `search` method with predicates, pagination, ordering, eager loading
  - Automatic model class derivation from repository name
  - Support for custom model class injection
- **`RepositoryAware` concern** - DSL for declaring repository dependencies in services
  - `repository :name` - Declare single repository with auto-derived class
  - `repository :name, class_name: "Custom::Repository"` - Custom repository class
  - `repository :name, as: :custom_accessor` - Custom accessor name
  - `repositories :user, :order, :payment` - Multiple repositories shorthand
  - Memoized repository instances per service execution
  - Private accessor methods for encapsulation

#### Documentation
- **Context7 FAQ Examples** (`context7/examples/04-faq-examples.md`) - 10 comprehensive code examples:
  1. Schema Validation with Dry::Schema
  2. Authorization with authorize_with
  3. Create Service with process/respond phases
  4. Pure Exception Pattern
  5. Transaction with Rollback
  6. Workflow with Service Composition
  7. Cache Management
  8. Generator Scaffold
  9. Conditional Branching Workflow with Rollback
  10. Multi-Layered Authorization
- **Repository Pattern Guide** (`docs/advanced/repository.md`) - Complete guide with:
  - BaseRepository usage and methods
  - RepositoryAware concern integration
  - Custom repository patterns
  - Predicates and search
  - Testing strategies
  - Best practices
- **Presenters Guide** (`docs/advanced/presenters.md`) - Complete presenter documentation

### Fixed

- **Async cache tests** - Fixed job count expectations with `cascade: false` option
- **Test isolation** - Improved test reliability for async invalidation tests

### Changed

- **Major version bump** - Indicates stable, production-ready API
- **687 tests passing** - Complete test coverage across all features

### Technical Details

**Repository Pattern Architecture:**
```
Service Layer
    │
    ▼
┌─────────────────────────────────┐
│  include RepositoryAware        │
│  repository :product            │
│                                 │
│  search_with do                 │
│    product_repository.published │
│  end                            │
└─────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────┐
│  ProductRepository              │
│    < BaseRepository             │
│                                 │
│  def published                  │
│    model.where(published: true) │
│  end                            │
└─────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────┐
│  Product < ApplicationRecord    │
└─────────────────────────────────┘
```

**Backward Compatibility:**
- All existing services continue to work unchanged
- Repository pattern is opt-in via `include RepositoryAware`
- No breaking changes to existing APIs

---

## [1.1.0] - 2025-11-13

### Added

#### Workflow Conditional Branching
- **`branch` DSL method** - Define conditional branch groups in workflows for multi-path execution
- **`on` DSL method** - Define conditional paths within branches with lambda conditions
- **`otherwise` DSL method** - Define default fallback path when no condition matches
- **Branch execution engine** - First-match semantics with single-path execution per branch
- **Nested branching support** - Unlimited depth for complex decision trees
- **Branch metadata tracking** - `branches_taken` metadata shows which branches executed
- **Selective rollback** - Only executed branch steps are rolled back on failure
- **Branch DSL classes**:
  - `BetterService::Workflows::Branch` - Individual conditional path representation
  - `BetterService::Workflows::BranchGroup` - Container for multiple branches
  - `BetterService::Workflows::BranchDSL` - DSL context for branch definition
- **Configuration error handling** - Raises `InvalidConfigurationError` when no branch matches without `otherwise`

#### Documentation
- **Complete branching documentation** across all workflow guides (6 files, 1,500+ lines):
  - Workflows introduction with branching overview and examples
  - Workflow steps with complete branch DSL reference
  - Workflow examples with 4 real-world branching scenarios (payment routing, approval workflows, user tiers, content processing)
  - Advanced workflows with branching patterns
  - Workflow generator with branching syntax guide
  - Testing guide with branch testing patterns
- **Context7 AI documentation** - Concise branching examples for AI code generation tools
- **README feature highlight** - Added branching to features list

#### Testing
- **Comprehensive test suite** for branching (42+ tests across 4 files):
  - Basic branching functionality tests
  - Integration tests with real database models
  - Edge cases and boundary conditions
  - Performance benchmarks
  - Real-world examples (e-commerce, approvals, subscriptions)

### Changed

- **Workflow DSL enhanced** - Added branch support while maintaining backward compatibility
- **Workflow execution** - Updated to handle both regular steps and branch groups polymorphically
- **Workflow result builder** - Enhanced metadata to include `branches_taken` array
- **Workflow base class** - Added `@branch_decisions` tracking

### Technical Details

**Branch Execution Rules:**
- Conditions evaluated in definition order (first-match wins)
- Only one branch path executes per `branch` block
- `otherwise` is optional but recommended (raises error if no match and no `otherwise`)
- Conditions receive full workflow context via lambda
- All branch decisions tracked in metadata format: `"branch_N:on_M"` or `"branch_N:otherwise"`

**Backward Compatibility:**
- All existing workflows continue to work unchanged
- No breaking changes to workflow API
- `branches_taken` metadata only included when branches are used

---

## [1.0.1] - 2025-11-12

### Added

#### Presenter System
- **`BetterService::Presenter` base class** - New presenter framework for transforming service data into view-friendly formats
  - `#as_json(opts)` - Override to define custom JSON representation
  - `#to_json(opts)` - JSON string serialization
  - `#to_h` - Hash representation alias
  - `#current_user` - Access current user from options
  - `#include_field?(field)` - Conditional field rendering
  - `#user_can?(role)` - Role-based permission checks
- **Presenter generator** (`rails generate better_service:presenter`) - Generate presenter classes and tests
- **Scaffold `--presenter` flag** - Generate presenter along with CRUD services

#### I18n Message System
- **Default locale file** (`config/locales/better_service.en.yml`) with standard success messages for all service actions
- **Enhanced message helper** with 3-level fallback chain (custom namespace → default → key)
- **Locale generator** (`rails generate better_service:locale`) - Generate I18n locale files with scaffolded translations
- **Service templates updated** - All CRUD generators now use `message("action.success")` instead of hardcoded strings

#### Cache Management
- **Automatic cache invalidation** for Create/Update/Destroy services
  - Enabled by default when `cache_contexts` are defined
  - `auto_invalidate_cache` DSL to disable/enable per service
  - Automatically invalidates after successful write operations
  - `should_auto_invalidate_cache?` helper method

#### Testing Infrastructure
- **`bin/test_all` script** - Comprehensive test suite runner with:
  - Automated tests (341 tests via `rake test`)
  - Manual service tests with Rails environment
  - Manual generator tests with validation
  - Manual integration tests with standalone database
  - Colored output with pass/fail tracking
  - Automatic service generation for missing dependencies

#### Documentation
- **Advanced guides** (9 comprehensive guides totaling 5,600+ lines):
  - Cache invalidation strategies
  - Error handling patterns
  - Workflow orchestration
  - Concerns reference
  - E-commerce implementation example
  - Testing strategies
- **Getting started guides** - Quick start and configuration reference
- **Generator documentation** - Complete generators overview and usage
- **Enhanced service documentation** with presenter integration examples

#### Generator Enhancements
- **Install generator** now copies default locale file to Rails app
- **Enhanced templates** with comprehensive comments and I18n examples

#### DSL Enhancements
- **`allow_nil_user` DSL method** - Explicit method for configuring nil user behavior
- **`auto_invalidate_cache` DSL method** - Control automatic cache invalidation per service

### Changed

- **Base service improvements** - `respond` method moved from Viewable concern to Base with cleaner implementation
- **LogSubscriber enhancements** - Added `detach` method and subscription tracking for better memory management
- **Service templates** - All CRUD templates updated to use I18n message helper
- **Generator tests** - Now enabled and running as part of main test suite
- **Integration tests** - Updated to use correct fully-qualified service class names

### Fixed

- **Integration test service class names** - Corrected paths to use `BetterService::Services::*` namespace
- **Validation error handling** - Fixed tests to properly catch `ValidationError` exceptions
- **Viewable concern cleanup** - Removed duplicate `respond` method override
- **Validatable concern cleanup** - Removed unused `valid?` method that conflicted with Pure Exception Pattern
- **Base service cleanup** - Removed deprecated `failure_result` and `error_result` methods

### Removed

- **Test files** for outdated examples (Article/Product services)
- **Deprecated methods**:
  - `Validatable#valid?` - Use exception handling instead
  - `Validatable#validation_errors` - Access via `ValidationError#context[:validation_errors]`
  - `Base#failure_result` - Services use Pure Exception Pattern
  - `Base#error_result` - Services use Pure Exception Pattern

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
