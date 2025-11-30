# Architecture Diagrams

Visual diagrams showing service execution flow with input/output for each phase.

---

## 5-Phase Service Flow

BetterService executes in **5 sequential phases**. Phase 1 runs during `initialize`, phases 2-5 run during `call`.

```mermaid
flowchart TD
    subgraph INIT["Service.new(user, params:)"]
        INPUT_INIT["INPUT: user, params hash"]
        P1[Phase 1: VALIDATION]
        OUTPUT_INIT["OUTPUT: validated @params"]
    end

    subgraph CALL["service.call"]
        P2[Phase 2: AUTHORIZATION]
        P3[Phase 3: SEARCH]
        P4[Phase 4: PROCESS]
        P5[Phase 5: RESPOND]
    end

    INPUT_INIT --> P1
    P1 -->|Valid| OUTPUT_INIT
    P1 -->|Invalid| ERR1[ValidationError]

    OUTPUT_INIT --> CALL
    P2 -->|Authorized| P3
    P2 -->|Not Authorized| ERR2[AuthorizationError]
    P3 -->|Data Found| P4
    P3 -->|Not Found| ERR3[ResourceNotFoundError]
    P4 -->|Success| P5
    P4 -->|Error| ERR4[ExecutionError]
    P5 --> RESULT([Result])
```

---

## Phase 1: VALIDATION

Runs during `Service.new(user, params:)` - validates and coerces parameters.

| Aspect | Details |
|--------|---------|
| **When** | During `Service.new(user, params:)` |
| **Input** | Raw `params` hash from caller |
| **Process** | Dry::Schema validation against `schema` block |
| **Output** | `@params` - validated, coerced hash |
| **On Error** | Raises `ValidationError` immediately |

```mermaid
flowchart LR
    A["params: {name: 'x', price: '10'}"] --> B[schema do...end]
    B --> C["@params: {name: 'x', price: 10.0}"]
    B -->|Invalid| D[ValidationError]
```

### DSL

```ruby
schema do
  required(:name).filled(:string, min_size?: 2)
  required(:price).filled(:decimal, gt?: 0)
  optional(:published).maybe(:bool)
end
```

---

## Phase 2: AUTHORIZATION

Runs first in `call` - checks user permissions before any data access.

| Aspect | Details |
|--------|---------|
| **When** | First step of `call`, BEFORE search |
| **Input** | `user`, `@params` |
| **Process** | Execute `authorize_with` block (if defined) |
| **Output** | `nil` (pass-through, no data modification) |
| **On Error** | Raises `AuthorizationError` |
| **Default** | If `authorize_with` NOT defined → **implicitly authorized** |

```mermaid
flowchart LR
    A[user, @params] --> B{authorize_with defined?}
    B -->|No| C[Proceed - default true]
    B -->|Yes| D[Execute block]
    D -->|truthy| C
    D -->|falsy| E[AuthorizationError]
```

### DSL

```ruby
# Optional - if not defined, authorization passes automatically
authorize_with do
  next true if user.admin?
  product = Product.find_by(id: params[:id])
  next false unless product
  product.user_id == user.id
end
```

### Default Behavior

If `authorize_with` is **NOT declared** in a service:
- No authorization check is performed
- The service proceeds directly to the Search phase
- Equivalent to always returning `true`

---

## Phase 3: SEARCH

Loads data required for business logic.

| Aspect | Details |
|--------|---------|
| **When** | After authorization passes |
| **Input** | `user`, `@params`, repositories |
| **Process** | Execute `search_with` block |
| **Output** | Hash with loaded data |
| **On Error** | Typically raises `ResourceNotFoundError` |

```mermaid
flowchart LR
    A[user, @params] --> B[search_with do...end]
    B --> C["{resource: Product}"]
    B --> D["{items: [Product, ...]}"]
    B -->|Not Found| E[ResourceNotFoundError]
```

### DSL

```ruby
search_with do
  product = product_repository.find(params[:id])
  { resource: product }
rescue ActiveRecord::RecordNotFound
  raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
    "Product not found",
    context: { id: params[:id] }
  )
end
```

### Output Convention

| Key | Usage |
|-----|-------|
| `{ resource: object }` | Single resource (Show, Update, Destroy) |
| `{ items: array }` | Collection (Index) |
| `{ }` | No data needed (Create) |

---

## Phase 4: PROCESS

Executes business logic and data transformations.

| Aspect | Details |
|--------|---------|
| **When** | After search completes |
| **Input** | `data` hash from search phase |
| **Process** | Execute `process_with` block |
| **Output** | Hash with transformed/created data |
| **On Error** | `DatabaseError`, `ExecutionError` |
| **Transaction** | Wrapped if `with_transaction true` |

```mermaid
flowchart LR
    A["{resource: product}"] --> B["process_with do |data|"]
    B --> C["product.update!(...)"]
    C --> D["{resource: product.reload}"]
    B -->|DB Error| E[DatabaseError]
```

### DSL

```ruby
process_with do |data|
  product = data[:resource]
  product_repository.update!(product, params.except(:id))
  { resource: product.reload }
end
```

### Transaction Support

```ruby
with_transaction true  # Wraps process phase in ActiveRecord::Base.transaction
```

---

## Phase 5: RESPOND

Formats the final response.

| Aspect | Details |
|--------|---------|
| **When** | After process completes |
| **Input** | `data` hash from process phase |
| **Process** | Execute `respond_with` block |
| **Output** | Final hash wrapped in `Result` object |
| **Presenter** | Transforms data if `presenter` defined |

```mermaid
flowchart LR
    A["{resource: product}"] --> B["respond_with do |data|"]
    B --> C["success_result(message, data)"]
    C --> D["Result.success(resource, meta)"]
```

### DSL

```ruby
respond_with do |data|
  success_result(message("update.success"), data)
end
```

### With Presenter

```ruby
presenter ProductPresenter  # Automatically wraps resource/items
```

---

## Complete Data Flow Example

End-to-end flow for an Update service.

```mermaid
flowchart TD
    subgraph "Phase 1: VALIDATION"
        I1["INPUT: {id: '5', name: 'New'}"]
        V1["schema { required(:id).filled(:integer) }"]
        O1["OUTPUT: @params = {id: 5, name: 'New'}"]
        I1 --> V1 --> O1
    end

    subgraph "Phase 2: AUTHORIZATION"
        I2["INPUT: user, @params"]
        V2["authorize_with { user.can_edit?(product) }"]
        O2["OUTPUT: nil (pass)"]
        I2 --> V2 --> O2
    end

    subgraph "Phase 3: SEARCH"
        I3["INPUT: user, @params"]
        V3["search_with { {resource: repo.find(5)} }"]
        O3["OUTPUT: {resource: #Product id:5}"]
        I3 --> V3 --> O3
    end

    subgraph "Phase 4: PROCESS"
        I4["INPUT: {resource: product}"]
        V4["process_with { product.update!(name: 'New') }"]
        O4["OUTPUT: {resource: product.reload}"]
        I4 --> V4 --> O4
    end

    subgraph "Phase 5: RESPOND"
        I5["INPUT: {resource: product}"]
        V5["respond_with { success_result(msg, data) }"]
        O5["OUTPUT: Result.success"]
        I5 --> V5 --> O5
    end

    O1 --> I2
    O2 --> I3
    O3 --> I4
    O4 --> I5
```

---

## Error Flow

All errors are caught and wrapped in `Result.failure`.

```mermaid
flowchart TD
    E1[ValidationError] --> R1[Result.failure]
    E2[AuthorizationError] --> R2[Result.failure]
    E3[ResourceNotFoundError] --> R3[Result.failure]
    E4[DatabaseError] --> R4[Result.failure]
    E5[ExecutionError] --> R5[Result.failure]

    R1 --> META1["meta: {error_code: :validation_failed}"]
    R2 --> META2["meta: {error_code: :unauthorized}"]
    R3 --> META3["meta: {error_code: :resource_not_found}"]
    R4 --> META4["meta: {error_code: :database_error}"]
    R5 --> META5["meta: {error_code: :execution_error}"]
```

---

## Quick Reference

| Phase | When | Input | Output | DSL |
|-------|------|-------|--------|-----|
| 1. Validation | `initialize` | raw params | `@params` | `schema do` |
| 2. Authorization | `call` start | user, params | nil | `authorize_with do` |
| 3. Search | after auth | user, params | `{resource:}` / `{items:}` | `search_with do` |
| 4. Process | after search | data hash | transformed data | `process_with do |data|` |
| 5. Respond | after process | data hash | `Result` | `respond_with do |data|` |
