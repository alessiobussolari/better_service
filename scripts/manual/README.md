# Manual Test Scripts

This directory contains manual testing scripts for BetterService development and debugging.

**These scripts are NOT executed by `rake test` or the automated test suite.**

## Scripts

### service_test.rb

Interactive test script for all service types with transaction rollback.

**Usage:**
```bash
cd test/dummy
bin/rails console
load '../../scripts/manual/service_test.rb'
```

**Or via rails runner:**
```bash
cd test/dummy
bin/rails runner '../../scripts/manual/service_test.rb'
```

**What it tests:**
- Create, Index, Show, Update, Destroy, Action services
- Validation and authorization
- Transaction support
- Error handling

**Features:**
- Runs in database transaction with automatic rollback
- Color-coded output (✓ passed, ✗ failed)
- Detailed test report at the end

---

### generator_test.rb

Manual testing script for all Rails generators.

**Usage:**
```bash
cd test/dummy
bin/rails runner '../../scripts/manual/generator_test.rb'
```

**What it tests:**
- Service generators (index, show, create, update, destroy, action)
- Workflow generator
- Scaffold generator
- Generator options (--cache, --authorize, --presenter)

**Features:**
- Automatic cleanup of generated files
- Colored output with status indicators
- Tests file creation and content validation

---

### integration_test.rb

Standalone integration test with in-memory SQLite database.

**Usage:**
```bash
ruby -Ilib scripts/manual/integration_test.rb
```

**What it tests:**
- ModelService functionality
- Messageable concern
- Validatable concern
- Viewable concern
- Cacheable concern

**Features:**
- No Rails app required
- In-memory database setup
- Self-contained test environment

---

## Why Manual Scripts?

These scripts serve different purposes than automated tests:

1. **Interactive debugging** - Step through service execution in console
2. **Visual verification** - See actual output and behavior
3. **Generator testing** - Verify generator output and file creation
4. **Integration verification** - Test complete flows with real data
5. **Development workflow** - Quick feedback during feature development

## Adding New Scripts

When adding new manual test scripts:

1. Place them in `scripts/manual/`
2. Add documentation to this README
3. Use descriptive filenames (e.g., `workflow_test.rb`, `cache_test.rb`)
4. Include usage instructions in file header comments
5. Make them executable: `chmod +x scripts/manual/your_script.rb`

## Running from Project Root

From project root, you can run:

```bash
# Service tests
cd test/dummy && bin/rails runner '../../scripts/manual/service_test.rb'

# Generator tests
cd test/dummy && bin/rails runner '../../scripts/manual/generator_test.rb'

# Integration tests
ruby -Ilib scripts/manual/integration_test.rb
```

## Note

- These scripts are excluded from the gem package
- They are not run by CI/CD
- They require a development environment setup
- Some require the test/dummy Rails app
