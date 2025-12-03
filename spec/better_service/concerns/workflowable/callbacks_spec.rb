# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterService::Concerns::Workflowable::Callbacks do
  # Create a test class that includes the Callbacks concern
  let(:workflow_class) do
    Class.new do
      include BetterService::Concerns::Workflowable::Callbacks

      attr_reader :execution_log

      def initialize
        @execution_log = []
      end
    end
  end

  # Context class for testing
  let(:user) { Struct.new(:id, :name).new(1, "Test User") }
  let(:context) { BetterService::Workflowable::Context.new(user) }

  describe "class-level DSL" do
    describe ".before_workflow" do
      it "adds callback to _before_workflow_callbacks" do
        workflow_class.before_workflow :validate_cart

        expect(workflow_class._before_workflow_callbacks).to include(:validate_cart)
      end

      it "allows multiple callbacks" do
        workflow_class.before_workflow :validate_cart
        workflow_class.before_workflow :check_inventory

        expect(workflow_class._before_workflow_callbacks).to eq([ :validate_cart, :check_inventory ])
      end

      it "does not modify parent class callbacks" do
        parent_class = Class.new { include BetterService::Concerns::Workflowable::Callbacks }
        parent_class.before_workflow :parent_callback

        child_class = Class.new(parent_class)
        child_class.before_workflow :child_callback

        expect(parent_class._before_workflow_callbacks).to eq([ :parent_callback ])
        expect(child_class._before_workflow_callbacks).to eq([ :parent_callback, :child_callback ])
      end
    end

    describe ".after_workflow" do
      it "adds callback to _after_workflow_callbacks" do
        workflow_class.after_workflow :send_notification

        expect(workflow_class._after_workflow_callbacks).to include(:send_notification)
      end

      it "allows multiple callbacks" do
        workflow_class.after_workflow :send_notification
        workflow_class.after_workflow :cleanup_temp_files

        expect(workflow_class._after_workflow_callbacks).to eq([ :send_notification, :cleanup_temp_files ])
      end
    end

    describe ".around_step" do
      it "adds callback to _around_step_callbacks" do
        workflow_class.around_step :log_execution

        expect(workflow_class._around_step_callbacks).to include(:log_execution)
      end

      it "allows multiple around callbacks" do
        workflow_class.around_step :log_execution
        workflow_class.around_step :measure_performance

        expect(workflow_class._around_step_callbacks).to eq([ :log_execution, :measure_performance ])
      end
    end
  end

  describe "#run_before_workflow_callbacks" do
    let(:workflow_with_before) do
      Class.new do
        include BetterService::Concerns::Workflowable::Callbacks

        attr_reader :execution_log

        before_workflow :first_callback
        before_workflow :second_callback

        def initialize
          @execution_log = []
        end

        def first_callback(context)
          @execution_log << :first
        end

        def second_callback(context)
          @execution_log << :second
        end

        def run_callbacks(context)
          run_before_workflow_callbacks(context)
        end
      end
    end

    it "executes callbacks in definition order" do
      workflow = workflow_with_before.new
      workflow.run_callbacks(context)

      expect(workflow.execution_log).to eq([ :first, :second ])
    end

    it "passes context to each callback" do
      workflow_class_with_context = Class.new do
        include BetterService::Concerns::Workflowable::Callbacks

        attr_reader :received_context

        before_workflow :capture_context

        def capture_context(ctx)
          @received_context = ctx
        end

        def run_callbacks(context)
          run_before_workflow_callbacks(context)
        end
      end

      workflow = workflow_class_with_context.new
      workflow.run_callbacks(context)

      expect(workflow.received_context).to eq(context)
    end

    it "stops execution when context is marked as failed" do
      workflow_class_with_failure = Class.new do
        include BetterService::Concerns::Workflowable::Callbacks

        attr_reader :execution_log

        before_workflow :fail_callback
        before_workflow :should_not_run

        def initialize
          @execution_log = []
        end

        def fail_callback(ctx)
          @execution_log << :failed
          ctx.fail!("Validation failed")
        end

        def should_not_run(ctx)
          @execution_log << :should_not_see_this
        end

        def run_callbacks(context)
          run_before_workflow_callbacks(context)
        end
      end

      workflow = workflow_class_with_failure.new
      workflow.run_callbacks(context)

      expect(workflow.execution_log).to eq([ :failed ])
      expect(workflow.execution_log).not_to include(:should_not_see_this)
      expect(context.failure?).to be true
    end

    it "handles no callbacks gracefully" do
      empty_workflow = Class.new do
        include BetterService::Concerns::Workflowable::Callbacks

        def run_callbacks(context)
          run_before_workflow_callbacks(context)
        end
      end

      workflow = empty_workflow.new
      expect { workflow.run_callbacks(context) }.not_to raise_error
    end
  end

  describe "#run_after_workflow_callbacks" do
    let(:workflow_with_after) do
      Class.new do
        include BetterService::Concerns::Workflowable::Callbacks

        attr_reader :execution_log

        after_workflow :first_after
        after_workflow :second_after

        def initialize
          @execution_log = []
        end

        def first_after(context)
          @execution_log << :first
        end

        def second_after(context)
          @execution_log << :second
        end

        def run_callbacks(context)
          run_after_workflow_callbacks(context)
        end
      end
    end

    it "executes all callbacks in order" do
      workflow = workflow_with_after.new
      workflow.run_callbacks(context)

      expect(workflow.execution_log).to eq([ :first, :second ])
    end

    it "executes even after failure (does not stop on failure)" do
      workflow_class_continue_after_fail = Class.new do
        include BetterService::Concerns::Workflowable::Callbacks

        attr_reader :execution_log

        after_workflow :first_after
        after_workflow :second_after

        def initialize
          @execution_log = []
        end

        def first_after(ctx)
          @execution_log << :first
          ctx.fail!("Something failed")
        end

        def second_after(ctx)
          @execution_log << :second
        end

        def run_callbacks(context)
          run_after_workflow_callbacks(context)
        end
      end

      workflow = workflow_class_continue_after_fail.new
      workflow.run_callbacks(context)

      # After callbacks should all run even if one fails the context
      expect(workflow.execution_log).to eq([ :first, :second ])
    end

    it "can access context state (success or failure)" do
      workflow_class_with_state_check = Class.new do
        include BetterService::Concerns::Workflowable::Callbacks

        attr_reader :context_was_successful

        after_workflow :check_state

        def check_state(ctx)
          @context_was_successful = ctx.success?
        end

        def run_callbacks(context)
          run_after_workflow_callbacks(context)
        end
      end

      workflow = workflow_class_with_state_check.new
      workflow.run_callbacks(context)

      expect(workflow.context_was_successful).to be true
    end
  end

  describe "#run_around_step_callbacks" do
    # Use a real Struct instead of RSpec double
    let(:step) { Struct.new(:name).new(:process_order) }

    it "executes the block when no callbacks defined" do
      empty_workflow = Class.new do
        include BetterService::Concerns::Workflowable::Callbacks

        attr_reader :block_executed

        def execute_step(step, context)
          run_around_step_callbacks(step, context) do
            @block_executed = true
          end
        end
      end

      workflow = empty_workflow.new
      workflow.execute_step(step, context)

      expect(workflow.block_executed).to be true
    end

    it "wraps block with single callback" do
      workflow_with_around = Class.new do
        include BetterService::Concerns::Workflowable::Callbacks

        attr_reader :execution_log

        around_step :log_step

        def initialize
          @execution_log = []
        end

        def log_step(step, context)
          @execution_log << :before_step
          yield
          @execution_log << :after_step
        end

        def execute_step(step, context)
          run_around_step_callbacks(step, context) do
            @execution_log << :step_executed
          end
        end
      end

      workflow = workflow_with_around.new
      workflow.execute_step(step, context)

      expect(workflow.execution_log).to eq([ :before_step, :step_executed, :after_step ])
    end

    it "chains multiple around callbacks in order" do
      workflow_with_chain = Class.new do
        include BetterService::Concerns::Workflowable::Callbacks

        attr_reader :execution_log

        around_step :outer_callback
        around_step :inner_callback

        def initialize
          @execution_log = []
        end

        def outer_callback(step, context)
          @execution_log << :outer_before
          yield
          @execution_log << :outer_after
        end

        def inner_callback(step, context)
          @execution_log << :inner_before
          yield
          @execution_log << :inner_after
        end

        def execute_step(step, context)
          run_around_step_callbacks(step, context) do
            @execution_log << :step_executed
          end
        end
      end

      workflow = workflow_with_chain.new
      workflow.execute_step(step, context)

      # Callbacks wrap like middlewares
      expect(workflow.execution_log).to eq([
        :outer_before,
        :inner_before,
        :step_executed,
        :inner_after,
        :outer_after
      ])
    end

    it "passes step and context to callback" do
      workflow_with_args = Class.new do
        include BetterService::Concerns::Workflowable::Callbacks

        attr_reader :received_step, :received_context

        around_step :capture_args

        def capture_args(step, context)
          @received_step = step
          @received_context = context
          yield
        end

        def execute_step(step, context)
          run_around_step_callbacks(step, context) { }
        end
      end

      workflow = workflow_with_args.new
      workflow.execute_step(step, context)

      expect(workflow.received_step).to eq(step)
      expect(workflow.received_context).to eq(context)
    end

    it "allows callback to skip step execution by not yielding" do
      workflow_skip_step = Class.new do
        include BetterService::Concerns::Workflowable::Callbacks

        attr_reader :step_executed

        around_step :skip_callback

        def initialize
          @step_executed = false
        end

        def skip_callback(step, context)
          # Don't yield - skip the step
        end

        def execute_step(step, context)
          run_around_step_callbacks(step, context) do
            @step_executed = true
          end
        end
      end

      workflow = workflow_skip_step.new
      workflow.execute_step(step, context)

      expect(workflow.step_executed).to be false
    end
  end

  describe "inheritance behavior" do
    it "inherits parent callbacks" do
      parent = Class.new do
        include BetterService::Concerns::Workflowable::Callbacks
        before_workflow :parent_before
        after_workflow :parent_after
      end

      child = Class.new(parent) do
        before_workflow :child_before
      end

      expect(child._before_workflow_callbacks).to eq([ :parent_before, :child_before ])
      expect(child._after_workflow_callbacks).to eq([ :parent_after ])
    end

    it "child callbacks don't affect parent" do
      parent = Class.new do
        include BetterService::Concerns::Workflowable::Callbacks
        before_workflow :parent_only
      end

      Class.new(parent) do
        before_workflow :child_only
      end

      expect(parent._before_workflow_callbacks).to eq([ :parent_only ])
    end
  end

  describe "default values" do
    it "has empty arrays by default" do
      fresh_class = Class.new { include BetterService::Concerns::Workflowable::Callbacks }

      expect(fresh_class._before_workflow_callbacks).to eq([])
      expect(fresh_class._after_workflow_callbacks).to eq([])
      expect(fresh_class._around_step_callbacks).to eq([])
    end
  end
end
