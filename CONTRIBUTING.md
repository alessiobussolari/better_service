# Contributing to BetterService

First off, thank you for considering contributing to BetterService! It's people like you that make BetterService such a great tool.

## Code of Conduct

This project and everyone participating in it is governed by our commitment to providing a welcoming and inspiring community for all. By participating, you are expected to uphold this standard.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the existing issues as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

* **Use a clear and descriptive title**
* **Describe the exact steps to reproduce the problem**
* **Provide specific examples** to demonstrate the steps
* **Describe the behavior you observed** and what you expected to see
* **Include code samples** and test cases if relevant
* **Include your environment details** (Ruby version, Rails version, OS)

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

* **Use a clear and descriptive title**
* **Provide a step-by-step description** of the suggested enhancement
* **Provide specific examples** to demonstrate the enhancement
* **Describe the current behavior** and **explain the behavior you expected** instead
* **Explain why this enhancement would be useful** to most BetterService users

### Pull Requests

* Fill in the pull request template
* Follow the Ruby style guide (use Rubocop)
* Include tests for your changes
* Update documentation as needed
* End all files with a newline
* Make sure all tests pass before submitting

## Development Setup

### Prerequisites

* Ruby >= 3.0.0
* Rails >= 8.1.1
* SQLite3

### Setup

1. Fork and clone the repository:
```bash
git clone https://github.com/YOUR_USERNAME/better_service.git
cd better_service
```

2. Install dependencies:
```bash
bundle install
```

3. Run the test suite:
```bash
bundle exec rake test
```

4. Set up the test Rails app:
```bash
cd test/dummy
bin/rails db:prepare
```

## Development Workflow

### Running Tests

Run the entire test suite:
```bash
bundle exec rake test
```

Run specific test file:
```bash
bundle exec ruby -Itest test/better_service/create_service_test.rb
```

Run specific test:
```bash
bundle exec ruby -Itest test/better_service/create_service_test.rb -n test_name
```

### Running Rubocop

Check code style:
```bash
bundle exec rubocop
```

Auto-fix issues:
```bash
bundle exec rubocop -a
```

### Manual Testing

Use the Rails console to test interactively:
```bash
cd test/dummy
bin/rails console
```

Or run the manual test script:
```bash
cd test/dummy
bin/rails runner 'load "../../manual_test.rb"'
```

## Coding Conventions

### Ruby Style

* Follow the [Ruby Style Guide](https://rubystyle.guide/)
* Use 2 spaces for indentation (no tabs)
* Keep lines under 120 characters
* Use `snake_case` for methods and variables
* Use `CamelCase` for classes and modules
* Add YARD documentation for public APIs

### Service Design

* Always use DSL methods (`process_with`, `search_with`, `respond_with`)
* Never override methods directly (`def process`, `def search`, `def respond`)
* Never call services from within other services - use workflows
* Always define a schema for parameter validation
* Include authorization checks when needed
* Write descriptive error messages

### Testing

* Write tests for all new features
* Maintain 100% test coverage for core functionality
* Use descriptive test names: `test "service does something when condition"`
* Follow AAA pattern: Arrange, Act, Assert
* Mock external dependencies
* Use fixtures or factories for test data

### Documentation

* Update README.md for major features
* Add examples to `/docs` for detailed documentation
* Create micro-examples in `/context7` for code snippets
* Include YARD comments for public APIs
* Update CHANGELOG.md following [Keep a Changelog](https://keepachangelog.com/)

### Git Commit Messages

* Use present tense ("Add feature" not "Added feature")
* Use imperative mood ("Move cursor to..." not "Moves cursor to...")
* Limit first line to 72 characters
* Reference issues and pull requests after first line

Example:
```
Add cache invalidation for workflow steps

- Invalidate cache contexts after each step completion
- Add tests for workflow cache behavior
- Update workflow documentation

Fixes #123
```

## Project Structure

```
better_service/
├── lib/
│   └── better_service/
│       ├── services/        # Service types
│       ├── concerns/        # Service concerns
│       ├── workflows/       # Workflow system
│       ├── subscribers/     # Instrumentation subscribers
│       ├── errors/          # Error classes
│       └── generators/      # Rails generators
├── test/
│   ├── better_service/      # Service tests
│   ├── concerns/            # Concern tests
│   ├── workflows/           # Workflow tests
│   ├── integration/         # Integration tests
│   └── dummy/               # Test Rails app
├── docs/                    # Detailed documentation
└── context7/                # Micro-example documentation
```

## Release Process

(For maintainers only)

1. Update version in `lib/better_service/version.rb`
2. Update `CHANGELOG.md` with release notes
3. Commit changes: `git commit -am "Release vX.Y.Z"`
4. Create git tag: `git tag vX.Y.Z`
5. Push changes: `git push origin main --tags`
6. Build gem: `bundle exec rake build`
7. Publish gem: `bundle exec rake release`
8. Create GitHub release with changelog

## Questions?

Feel free to open an issue for questions or reach out to the maintainers.

## License

By contributing to BetterService, you agree that your contributions will be licensed under the MIT License.
