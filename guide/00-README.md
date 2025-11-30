# BetterService Guides

Step-by-step tutorials for learning BetterService.

---

## Prerequisites

### Required Knowledge

What you should know before starting.

```ruby
# Ruby basics: classes, blocks, modules
# Rails basics: models, controllers, ActiveRecord
# Basic understanding of service objects concept
```

--------------------------------

## Learning Path

### Recommended Order

Follow these guides in order for best results.

```
1. Your First Service     → Basic service structure
2. CRUD Services          → Generate full resource services
3. Authorization          → Permission patterns
4. Validation             → Schema validation
5. Repositories           → Data access layer
6. Workflows              → Multi-step orchestration
7. Error Handling         → Exception management
8. Testing                → Test your services
9. Real-World Example     → Complete application
```

--------------------------------

## Quick Start

### Minimal Service

The simplest possible service to understand the pattern.

```ruby
class Greeting::SayHelloService < BetterService::Services::Base
  schema do
    required(:name).filled(:string)
  end

  process_with do
    { resource: "Hello, #{params[:name]}!" }
  end
end

# Usage
result = Greeting::SayHelloService.new(current_user, params: { name: "World" }).call
result.resource  # => "Hello, World!"
```

--------------------------------

## Guide Index

### Available Tutorials

All guides in this folder.

```
00-README.md              → This file (index)
01-your-first-service.md  → Create your first service
02-crud-services.md       → Full CRUD implementation
03-authorization.md       → Permission patterns
04-validation.md          → Schema validation
05-repositories.md        → Repository pattern
06-workflows.md           → Building workflows
07-error-handling.md      → Error management
08-testing.md             → Testing services
09-real-world-example.md  → Complete e-commerce example
```

--------------------------------

## Getting Help

### Resources

Where to find more information.

```ruby
# Documentation folders:
# - context7/  → Technical API reference
# - docs/      → User documentation
# - guide/     → Tutorials (this folder)

# Key files:
# - llms.txt       → Quick reference
# - context7.json  → Project configuration
# - CLAUDE.md      → Development guide
```

--------------------------------
