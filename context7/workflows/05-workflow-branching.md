# Workflow Branching

Workflows support **conditional branching** for non-linear execution paths. Only one branch executes based on the first matching condition.

## Basic Syntax

```ruby
class MyWorkflow < BetterService::Workflows::Base
  step :validate, with: ValidateService

  branch do
    on ->(ctx) { ctx.validate.type == "premium" } do
      step :premium_flow, with: PremiumService
    end

    on ->(ctx) { ctx.validate.type == "standard" } do
      step :standard_flow, with: StandardService
    end

    otherwise do
      step :default_flow, with: DefaultService
    end
  end

  step :finalize, with: FinalizeService
end
```

## DSL Reference

### `branch do ... end`

Creates a branch group containing conditional paths:

```ruby
branch do
  # on blocks and otherwise block go here
end
```

### `on ->(ctx) { condition } do ... end`

Defines a conditional branch:

```ruby
on ->(ctx) { ctx.user.premium? } do
  step :premium_feature, with: PremiumService
end
```

- **Condition**: Lambda receiving context (`ctx`)
- **Access**: `ctx.user`, `ctx.params`, `ctx.step_name` (previous step results)
- **First-match wins**: Conditions evaluated in order

### `otherwise do ... end`

Default branch when no conditions match:

```ruby
otherwise do
  step :fallback, with: FallbackService
end
```

- **Optional**: But without it, an error is raised if no condition matches
- **Single**: Only one `otherwise` per branch block

## Branch Execution Rules

1. **Conditions evaluated in order** - First true condition's branch executes
2. **Single path execution** - Only ONE branch runs per `branch` block
3. **Otherwise is optional** - But raises `InvalidConfigurationError` if no match
4. **Steps after branch always execute** - Unless workflow fails

## Examples

### Payment Method Routing

```ruby
class Order::ProcessPaymentWorkflow < BetterService::Workflows::Base
  with_transaction true

  step :validate_order,
       with: Order::ValidateService,
       input: ->(ctx) { { order_id: ctx.order_id } }

  branch do
    on ->(ctx) { ctx.validate_order.payment_method == "credit_card" } do
      step :charge_credit_card,
           with: Payment::ChargeCreditCardService,
           input: ->(ctx) { { order: ctx.validate_order } },
           rollback: ->(ctx) { Payment::RefundService.call(ctx.charge_credit_card.id) }

      step :verify_3d_secure,
           with: Payment::Verify3DSecureService,
           input: ->(ctx) { { charge: ctx.charge_credit_card } },
           optional: true
    end

    on ->(ctx) { ctx.validate_order.payment_method == "paypal" } do
      step :create_paypal_order,
           with: Payment::Paypal::CreateOrderService,
           input: ->(ctx) { { order: ctx.validate_order } }

      step :capture_paypal_payment,
           with: Payment::Paypal::CaptureService,
           input: ->(ctx) { { paypal_order: ctx.create_paypal_order } }
    end

    on ->(ctx) { ctx.validate_order.payment_method == "bank_transfer" } do
      step :generate_transfer_reference,
           with: Payment::BankTransfer::GenerateReferenceService,
           input: ->(ctx) { { order: ctx.validate_order } }

      step :send_transfer_instructions,
           with: Email::BankInstructionsService,
           input: ->(ctx) { { order: ctx.validate_order, reference: ctx.generate_transfer_reference } }
    end

    otherwise do
      step :unsupported_payment,
           with: Payment::UnsupportedMethodService,
           input: ->(ctx) { { method: ctx.validate_order.payment_method } }
    end
  end

  step :update_order_status,
       with: Order::UpdateStatusService,
       input: ->(ctx) { { order_id: ctx.validate_order.id, status: "processing" } }

  step :send_confirmation,
       with: Email::OrderConfirmationService,
       input: ->(ctx) { { order: ctx.validate_order } }
end
```

### Nested Branches

Branches can contain other branches:

```ruby
class Document::ApprovalWorkflow < BetterService::Workflows::Base
  step :validate_document,
       with: Document::ValidateService

  branch do
    on ->(ctx) { ctx.validate_document.type == "contract" } do
      step :legal_review,
           with: Legal::ReviewService

      # Nested branch based on contract value
      branch do
        on ->(ctx) { ctx.validate_document.value > 100_000 } do
          step :ceo_approval,
               with: Approval::CEOService

          step :board_approval,
               with: Approval::BoardService
        end

        on ->(ctx) { ctx.validate_document.value > 10_000 } do
          step :manager_approval,
               with: Approval::ManagerService
        end

        otherwise do
          step :supervisor_approval,
               with: Approval::SupervisorService
        end
      end
    end

    on ->(ctx) { ctx.validate_document.type == "invoice" } do
      branch do
        on ->(ctx) { ctx.validate_document.amount > 5_000 } do
          step :finance_approval,
               with: Approval::FinanceService
        end

        otherwise do
          step :auto_approve,
               with: Approval::AutoApproveService
        end
      end
    end

    otherwise do
      step :standard_approval,
           with: Approval::StandardService
    end
  end

  step :finalize_document,
       with: Document::FinalizeService
end
```

### Complex Conditions

Conditions can use any Ruby logic:

```ruby
branch do
  # Multiple conditions with AND
  on ->(ctx) {
    ctx.user.account_type == "enterprise" &&
    ctx.subscription.custom_billing? &&
    ctx.subscription.annual_value > 50_000
  } do
    step :enterprise_flow, with: Enterprise::CustomFlowService
  end

  # Conditions with method calls
  on ->(ctx) {
    ctx.user.premium? &&
    ctx.payment_method.present? &&
    ctx.payment_method.valid? &&
    ctx.payment_method.expires_at > 30.days.from_now
  } do
    step :premium_flow, with: Premium::FlowService
  end

  # Simple condition
  on ->(ctx) { ctx.user.free_tier? } do
    step :free_flow, with: Free::FlowService
  end

  otherwise do
    step :default_flow, with: Default::FlowService
  end
end
```

## Branch Metadata

Workflow results include `branches_taken` tracking:

```ruby
result = Order::ProcessPaymentWorkflow.new(user, params: { order_id: 123 }).call

result[:metadata]
# => {
#   workflow: "Order::ProcessPaymentWorkflow",
#   steps_executed: [:validate_order, :charge_credit_card, :verify_3d_secure, :update_order_status, :send_confirmation],
#   branches_taken: ["branch_1:on_1"],
#   duration_ms: 1234.56
# }
```

### Branch Decision Format

- **Single branch**: `"branch_1:on_1"` (first branch, first condition)
- **Second condition**: `"branch_1:on_2"`
- **Otherwise**: `"branch_1:otherwise"`
- **Nested branches**: `["branch_1:on_1", "nested_branch_1:on_2"]`

```ruby
# Nested branch tracking
result[:metadata][:branches_taken]
# => ["branch_1:on_1", "nested_branch_1:otherwise"]
# Outer branch took first condition, nested took otherwise
```

## Rollback Behavior

When a step fails in a branch:

1. **Only executed steps are rolled back** - Not steps from non-executed branches
2. **Reverse order (LIFO)** - Last executed step rolled back first
3. **Each step's rollback block is called** if defined

```ruby
branch do
  on ->(ctx) { ctx.user.premium? } do
    step :create_premium_subscription,
         with: Subscription::CreatePremiumService,
         rollback: ->(ctx) { Subscription::CancelService.call(ctx.create_premium_subscription.id) }

    step :charge_annual_fee,  # If this fails...
         with: Payment::ChargeAnnualService,
         rollback: ->(ctx) { Payment::RefundService.call(ctx.charge_annual_fee.id) }
  end

  otherwise do
    # These steps are NEVER rolled back because they never executed
    step :create_free_subscription,
         with: Subscription::CreateFreeService
  end
end
```

## Error Handling

### No Matching Branch

Without `otherwise`, raises error if no condition matches:

```ruby
branch do
  on ->(ctx) { ctx.type == "A" } do
    step :handle_a, with: HandleAService
  end

  on ->(ctx) { ctx.type == "B" } do
    step :handle_b, with: HandleBService
  end
  # No otherwise - will raise if type is "C"
end
```

```ruby
# Raises:
BetterService::Errors::Configuration::InvalidConfigurationError
# Message: "No matching branch found and no otherwise block defined"
```

### Step Failure in Branch

```ruby
begin
  result = MyWorkflow.new(user, params: params).call
rescue BetterService::Errors::Workflowable::Runtime::StepExecutionError => e
  puts e.message            # "Step failed: charge_payment"
  puts e.context[:step]     # :charge_payment
  puts e.context[:workflow] # "MyWorkflow"
end
```

## Testing Branches

### Test Each Path

```ruby
class PaymentWorkflowTest < ActiveSupport::TestCase
  test "credit card path" do
    order = create_order(payment_method: "credit_card")

    result = Order::ProcessPaymentWorkflow.new(user, params: { order_id: order.id }).call

    assert result[:success]
    assert_includes result[:metadata][:steps_executed], :charge_credit_card
    assert_includes result[:metadata][:branches_taken], "branch_1:on_1"
  end

  test "paypal path" do
    order = create_order(payment_method: "paypal")

    result = Order::ProcessPaymentWorkflow.new(user, params: { order_id: order.id }).call

    assert result[:success]
    assert_includes result[:metadata][:steps_executed], :create_paypal_order
    assert_includes result[:metadata][:branches_taken], "branch_1:on_2"
  end

  test "otherwise path" do
    order = create_order(payment_method: "unknown")

    result = Order::ProcessPaymentWorkflow.new(user, params: { order_id: order.id }).call

    assert result[:success]
    assert_includes result[:metadata][:branches_taken], "branch_1:otherwise"
  end
end
```

### Test Nested Branches

```ruby
test "nested branch tracking" do
  document = create_document(type: "contract", value: 150_000)

  result = Document::ApprovalWorkflow.new(user, params: { document_id: document.id }).call

  assert result[:success]
  assert_equal 2, result[:metadata][:branches_taken].count
  assert_includes result[:metadata][:branches_taken], "branch_1:on_1"      # contract path
  assert_includes result[:metadata][:branches_taken], "nested_branch_1:on_1"  # high value path
  assert_includes result[:metadata][:steps_executed], :ceo_approval
  assert_includes result[:metadata][:steps_executed], :board_approval
end
```

## Critical Rules

### Always Provide Otherwise (Recommended)

```ruby
# Good - explicit fallback
branch do
  on ->(ctx) { ctx.type == "A" } do
    step :handle_a, with: HandleAService
  end

  otherwise do
    step :handle_unknown, with: HandleUnknownService
  end
end

# Risky - may raise at runtime
branch do
  on ->(ctx) { ctx.type == "A" } do
    step :handle_a, with: HandleAService
  end
  # No otherwise - will raise if type != "A"
end
```

### Conditions Must Be Lambdas

```ruby
# Correct
on ->(ctx) { ctx.user.premium? } do
  # ...
end

# Wrong - will not work
on ctx.user.premium? do
  # ...
end
```

### Steps Inside Branch Blocks Only

```ruby
# Correct
branch do
  on ->(ctx) { condition } do
    step :my_step, with: MyService  # Inside on block
  end
end

# Wrong - step outside branch blocks
branch do
  step :my_step, with: MyService  # Error!
end
```
