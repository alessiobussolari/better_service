# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authorizable concern" do
  # Mock user class
  let(:mock_user_class) do
    Class.new do
      attr_accessor :id, :admin

      def initialize(id:, admin: false)
        @id = id
        @admin = admin
      end

      def admin?
        @admin
      end
    end
  end

  let(:admin_user) { mock_user_class.new(id: 1, admin: true) }
  let(:non_admin_user) { mock_user_class.new(id: 2, admin: false) }

  # Test service WITH authorization
  let(:authorized_service_class) do
    Class.new(BetterService::Services::Base) do
      self._allow_nil_user = true

      schema do
        required(:action).filled(:string)
      end

      authorize_with do
        user&.admin? == true
      end

      search_with do
        { data: "searched" }
      end

      process_with do |data|
        { result: "processed", data: data }
      end

      respond_with do |data|
        { object: data[:result], success: true }
      end
    end
  end

  # Test service WITHOUT authorization
  let(:unauthorized_service_class) do
    Class.new(BetterService::Services::Base) do
      self._allow_nil_user = true

      schema do
        required(:action).filled(:string)
      end

      search_with do
        { data: "searched" }
      end

      process_with do |_data|
        { result: "processed" }
      end

      respond_with do |data|
        { object: data[:result], success: true }
      end
    end
  end

  # Test service with authorization that uses params
  let(:params_based_auth_service_class) do
    mock_user_class_ref = mock_user_class
    Class.new(BetterService::Services::Base) do
      schema do
        required(:user_id).filled(:integer)
      end

      authorize_with do
        params[:user_id] == user&.id
      end

      search_with do
        { data: "searched" }
      end

      process_with do |_data|
        { result: "authorized user" }
      end

      respond_with do |data|
        { object: data[:result], success: true }
      end
    end
  end

  # Test service with authorization that checks resource ownership
  let(:resource_ownership_service_class) do
    Class.new(BetterService::Services::Base) do
      schema do
        required(:id).filled(:integer)
      end

      authorize_with do
        @resource = { id: params[:id], owner_id: 1 }
        @resource[:owner_id] == user&.id
      end

      search_with do
        { resource: @resource }
      end

      process_with do |data|
        { result: "owner verified", resource: data[:resource] }
      end

      respond_with do |data|
        { object: data[:result], resource: data[:resource], success: true }
      end
    end
  end

  describe "authorization passes" do
    it "continues normally when block returns true" do
      result, meta = authorized_service_class.new(admin_user, params: { action: "test" }).call

      expect(meta[:success]).to be true
      expect(result).to eq("processed")
    end
  end

  describe "authorization fails" do
    it "returns error when block returns false" do
      _result, meta = authorized_service_class.new(non_admin_user, params: { action: "test" }).call

      expect(meta[:success]).to be false
      expect(meta[:error_code]).to eq(:unauthorized)
    end

    it "returns error when user is nil" do
      _result, meta = authorized_service_class.new(nil, params: { action: "test" }).call

      expect(meta[:success]).to be false
      expect(meta[:error_code]).to eq(:unauthorized)
    end
  end

  describe "service without authorization" do
    it "works normally" do
      result, meta = unauthorized_service_class.new(nil, params: { action: "test" }).call

      expect(meta[:success]).to be true
      expect(result).to eq("processed")
    end
  end

  describe "authorization access to params" do
    it "passes when params match" do
      user = mock_user_class.new(id: 42, admin: false)
      _result, meta = params_based_auth_service_class.new(user, params: { user_id: 42 }).call

      expect(meta[:success]).to be true
    end

    it "fails when params do not match" do
      user = mock_user_class.new(id: 42, admin: false)
      _result, meta = params_based_auth_service_class.new(user, params: { user_id: 99 }).call

      expect(meta[:success]).to be false
      expect(meta[:error_code]).to eq(:unauthorized)
    end
  end

  describe "authorization access to user object" do
    it "can check user properties" do
      user = mock_user_class.new(id: 1, admin: true)
      _result, meta = authorized_service_class.new(user, params: { action: "test" }).call

      expect(meta[:success]).to be true
    end
  end

  describe "authorization can load and cache resources" do
    it "resources are reused in search" do
      user = mock_user_class.new(id: 1, admin: false)
      result, meta = resource_ownership_service_class.new(user, params: { id: 123 }).call

      expect(meta[:success]).to be true
      expect(result).to eq("owner verified")
    end
  end

  describe "authorization prevents search execution" do
    it "search is not executed on auth failure" do
      search_executed = false

      service_class = Class.new(BetterService::Services::Base) do
        self._allow_nil_user = true

        schema { required(:action).filled(:string) }

        authorize_with do
          false
        end

        search_with do
          search_executed = true
          { data: "should not execute" }
        end

        process_with do |data|
          { result: "should not execute" }
        end

        respond_with do |data|
          { object: data[:result], success: true }
        end
      end

      _result, meta = service_class.new(nil, params: { action: "test" }).call

      expect(meta[:success]).to be false
      expect(meta[:error_code]).to eq(:unauthorized)
      expect(search_executed).to be false
    end
  end

  describe "authorization with Pundit-style policies" do
    it "integrates with policy pattern" do
      policy_class = Class.new do
        def initialize(user, record)
          @user = user
          @record = record
        end

        def update?
          @user&.admin? == true
        end
      end

      service_class = Class.new(BetterService::Services::Base) do
        schema { required(:id).filled(:integer) }

        define_method(:policy_class) { policy_class }

        authorize_with do
          resource = { id: params[:id] }
          policy_class.new(user, resource).update?
        end

        search_with { { resource: "found" } }
        process_with { |_data| { result: "updated" } }

        respond_with do |data|
          { object: data[:result], success: true }
        end
      end

      _result, meta = service_class.new(admin_user, params: { id: 123 }).call
      expect(meta[:success]).to be true

      _result, fail_meta = service_class.new(non_admin_user, params: { id: 123 }).call
      expect(fail_meta[:success]).to be false
      expect(fail_meta[:error_code]).to eq(:unauthorized)
    end
  end

  describe "authorization with CanCanCan-style abilities" do
    it "integrates with ability pattern" do
      ability_class = Class.new do
        def initialize(user)
          @user = user
        end

        def can?(action, subject)
          @user&.admin? == true && action == :destroy
        end
      end

      service_class = Class.new(BetterService::Services::Base) do
        schema { required(:id).filled(:integer) }

        define_method(:ability_class) { ability_class }

        authorize_with do
          ability_class.new(user).can?(:destroy, :product)
        end

        search_with { { resource: "found" } }
        process_with { |_data| { result: "destroyed" } }

        respond_with do |data|
          { object: data[:result], success: true }
        end
      end

      _result, meta = service_class.new(admin_user, params: { id: 123 }).call
      expect(meta[:success]).to be true

      _result, fail_meta = service_class.new(non_admin_user, params: { id: 123 }).call
      expect(fail_meta[:success]).to be false
    end
  end

  describe "authorization with custom logic" do
    it "works with secret key validation" do
      service_class = Class.new(BetterService::Services::Base) do
        schema { required(:secret_key).filled(:string) }

        authorize_with do
          params[:secret_key] == "super-secret-123" && user&.id&.positive?
        end

        search_with { { data: "secure data" } }
        process_with { |_data| { result: "access granted" } }

        respond_with do |data|
          { object: data[:result], success: true }
        end
      end

      user = mock_user_class.new(id: 1)

      _result, meta = service_class.new(user, params: { secret_key: "super-secret-123" }).call
      expect(meta[:success]).to be true

      _result, fail_meta = service_class.new(user, params: { secret_key: "wrong" }).call
      expect(fail_meta[:success]).to be false
      expect(fail_meta[:error_code]).to eq(:unauthorized)
    end
  end

  describe "authorization with service types" do
    it "works with create-style service" do
      service_class = Class.new(BetterService::Services::Base) do
        performed_action :created
        with_transaction true

        schema { required(:name).filled(:string) }

        authorize_with do
          user&.admin? == true
        end

        search_with { {} }
        process_with { |_data| { object: { name: params[:name] } } }

        respond_with do |data|
          { object: data[:object], success: true }
        end
      end

      _result, meta = service_class.new(admin_user, params: { name: "Test" }).call
      expect(meta[:success]).to be true
      expect(meta[:action]).to eq(:created)

      _result, fail_meta = service_class.new(non_admin_user, params: { name: "Test" }).call
      expect(fail_meta[:success]).to be false
      expect(fail_meta[:error_code]).to eq(:unauthorized)
    end

    it "works with update-style service" do
      service_class = Class.new(BetterService::Services::Base) do
        performed_action :updated
        with_transaction true

        schema { required(:id).filled(:integer) }

        authorize_with do
          user&.admin? == true
        end

        search_with { { resource: { id: params[:id] } } }
        process_with { |data| { object: data[:resource] } }

        respond_with do |data|
          { object: data[:object], success: true }
        end
      end

      _result, meta = service_class.new(admin_user, params: { id: 1 }).call
      expect(meta[:success]).to be true
      expect(meta[:action]).to eq(:updated)
    end

    it "works with action services" do
      service_class = Class.new(BetterService::Services::Base) do
        performed_action :publish
        schema { required(:id).filled(:integer) }

        authorize_with do
          user&.admin? == true
        end

        search_with { { resource: { id: params[:id] } } }
        process_with { |data| { object: data[:resource] } }

        respond_with do |data|
          { object: data[:object], success: true }
        end
      end

      _result, meta = service_class.new(admin_user, params: { id: 1 }).call
      expect(meta[:success]).to be true
      expect(meta[:action]).to eq(:publish)
    end
  end
end
