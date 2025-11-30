# Generators

Reference for BetterService Rails generators.

---

## Installation

### Install Generator

Set up BetterService in your application.

```bash
rails g better_service:install
```

Creates:
- `config/initializers/better_service.rb`
- `config/locales/better_service.en.yml`

--------------------------------

## Service Generators

### Base Generator

Generate the foundation for a resource's services.

```bash
rails g serviceable:base Product
```

Creates:
- `app/services/product/base_service.rb`
- `app/repositories/product_repository.rb`
- `config/locales/product_services.en.yml`
- `test/services/product/base_service_test.rb`
- `test/repositories/product_repository_test.rb`

Options:
- `--skip_repository` - Skip repository generation
- `--skip_locale` - Skip locale file
- `--skip_test` - Skip test files

--------------------------------

### Scaffold Generator

Generate all CRUD services at once.

```bash
rails g serviceable:scaffold Product --base
```

Creates:
- BaseService + Repository + Locale
- IndexService
- ShowService
- CreateService
- UpdateService
- DestroyService
- All test files

Options:
- `--base` - Generate BaseService (recommended)
- `--presenter` - Generate presenter class
- `--skip_repository` - Skip repository
- `--skip_locale` - Skip locale file
- `--skip_test` - Skip test files

--------------------------------

### Index Generator

Generate an Index service.

```bash
rails g serviceable:index Product
rails g serviceable:index Product --base_class=Product::BaseService
```

Creates:
- `app/services/product/index_service.rb`
- `test/services/product/index_service_test.rb`

--------------------------------

### Show Generator

Generate a Show service.

```bash
rails g serviceable:show Product
rails g serviceable:show Product --base_class=Product::BaseService
```

Creates:
- `app/services/product/show_service.rb`
- `test/services/product/show_service_test.rb`

--------------------------------

### Create Generator

Generate a Create service.

```bash
rails g serviceable:create Product
rails g serviceable:create Product --base_class=Product::BaseService
```

Creates:
- `app/services/product/create_service.rb`
- `test/services/product/create_service_test.rb`

--------------------------------

### Update Generator

Generate an Update service.

```bash
rails g serviceable:update Product
rails g serviceable:update Product --base_class=Product::BaseService
```

Creates:
- `app/services/product/update_service.rb`
- `test/services/product/update_service_test.rb`

--------------------------------

### Destroy Generator

Generate a Destroy service.

```bash
rails g serviceable:destroy Product
rails g serviceable:destroy Product --base_class=Product::BaseService
```

Creates:
- `app/services/product/destroy_service.rb`
- `test/services/product/destroy_service_test.rb`

--------------------------------

### Action Generator

Generate a custom action service.

```bash
rails g serviceable:action Product publish
rails g serviceable:action Product approve --base_class=Product::BaseService
```

Creates:
- `app/services/product/publish_service.rb`
- `test/services/product/publish_service_test.rb`

--------------------------------

## Workflow Generator

### Generate Workflow

Create a workflow for orchestrating services.

```bash
rails g serviceable:workflow Order::Checkout
rails g serviceable:workflow Subscription::Renewal
```

Creates:
- `app/workflows/order/checkout_workflow.rb`
- `test/workflows/order/checkout_workflow_test.rb`

--------------------------------

## Utility Generators

### Presenter Generator

Generate a presenter class.

```bash
rails g better_service:presenter Product
```

Creates:
- `app/presenters/product_presenter.rb`
- `test/presenters/product_presenter_test.rb`

--------------------------------

### Locale Generator

Generate a locale file.

```bash
rails g better_service:locale products
```

Creates:
- `config/locales/products_services.en.yml`

--------------------------------

## Namespaced Resources

### Generate with Namespaces

All generators support namespaces.

```bash
# Admin namespace
rails g serviceable:base Admin::Product
rails g serviceable:scaffold Admin::Product --base

# API versioning
rails g serviceable:base Api::V1::Product
rails g serviceable:scaffold Api::V1::Product --base

# Custom action with namespace
rails g serviceable:action Admin::Product approve --base_class=Admin::Product::BaseService

# Workflow with namespace
rails g serviceable:workflow Admin::User::Onboarding
```

--------------------------------

## Generated Structure

### After Full Generation

File structure after generating everything for Product.

```
app/
├── presenters/
│   └── product_presenter.rb
├── repositories/
│   └── product_repository.rb
├── services/
│   └── product/
│       ├── base_service.rb
│       ├── index_service.rb
│       ├── show_service.rb
│       ├── create_service.rb
│       ├── update_service.rb
│       ├── destroy_service.rb
│       └── publish_service.rb
└── workflows/
    └── product/
        └── bulk_import_workflow.rb

config/
└── locales/
    └── product_services.en.yml

test/
├── presenters/
│   └── product_presenter_test.rb
├── repositories/
│   └── product_repository_test.rb
├── services/
│   └── product/
│       ├── base_service_test.rb
│       ├── index_service_test.rb
│       ├── show_service_test.rb
│       ├── create_service_test.rb
│       ├── update_service_test.rb
│       ├── destroy_service_test.rb
│       └── publish_service_test.rb
└── workflows/
    └── product/
        └── bulk_import_workflow_test.rb
```

--------------------------------

## Quick Reference

### Generator Commands

Summary of all generator commands.

```bash
# Setup
rails g better_service:install

# Full scaffold
rails g serviceable:scaffold Product --base --presenter

# Base only
rails g serviceable:base Product

# Individual services
rails g serviceable:index Product --base_class=Product::BaseService
rails g serviceable:show Product --base_class=Product::BaseService
rails g serviceable:create Product --base_class=Product::BaseService
rails g serviceable:update Product --base_class=Product::BaseService
rails g serviceable:destroy Product --base_class=Product::BaseService

# Custom actions
rails g serviceable:action Product publish --base_class=Product::BaseService
rails g serviceable:action Product archive --base_class=Product::BaseService

# Workflows
rails g serviceable:workflow Order::Checkout

# Utilities
rails g better_service:presenter Product
rails g better_service:locale products
```

--------------------------------

## Recommended Workflow

### Step-by-Step Setup

Recommended order for setting up a new resource.

```bash
# 1. Install BetterService (once per project)
rails g better_service:install

# 2. Generate base infrastructure
rails g serviceable:base Product

# 3. Generate all CRUD services
rails g serviceable:scaffold Product --base --presenter

# 4. Add custom actions as needed
rails g serviceable:action Product publish --base_class=Product::BaseService
rails g serviceable:action Product archive --base_class=Product::BaseService

# 5. Create workflows for complex operations
rails g serviceable:workflow Product::BulkImport
```

--------------------------------
