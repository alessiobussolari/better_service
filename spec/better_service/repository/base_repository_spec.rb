# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterService::Repository::BaseRepository do
  # Create a test repository class that uses User model from rails_app
  let(:user_repository_class) do
    Class.new(described_class) do
      def initialize
        super(User)
      end
    end
  end

  let(:repository) { user_repository_class.new }

  # Create test users for specs
  let!(:user1) { User.create!(name: "Alice", email: "alice@example.com", admin: false) }
  let!(:user2) { User.create!(name: "Bob", email: "bob@example.com", admin: true) }
  let!(:user3) { User.create!(name: "Charlie", email: "charlie@example.com", admin: false) }

  describe "#initialize" do
    context "with explicit model class" do
      it "sets the model attribute" do
        repo = described_class.new(User)
        expect(repo.model).to eq(User)
      end
    end

    context "deriving model class from repository name" do
      it "derives UserRepository -> User" do
        # Define UserRepository at runtime
        stub_const("UserRepository", Class.new(described_class))
        repo = UserRepository.new
        expect(repo.model).to eq(User)
      end

      it "raises ConfigurationError for invalid class name" do
        stub_const("InvalidModelRepository", Class.new(described_class))

        expect { InvalidModelRepository.new }.to raise_error(
          BetterService::Errors::Configuration::ConfigurationError,
          /Could not derive model class/
        )
      end
    end
  end

  describe "#search" do
    context "with default parameters" do
      it "returns an ActiveRecord::Relation" do
        result = repository.search
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "returns all records with default pagination" do
        result = repository.search
        expect(result.to_a).to include(user1, user2, user3)
      end
    end

    context "with limit: 1" do
      it "returns a single record" do
        result = repository.search({}, limit: 1)
        expect(result).to be_a(User)
      end
    end

    context "with limit: Integer > 1" do
      it "limits results to N records" do
        result = repository.search({}, limit: 2)
        expect(result).to be_a(ActiveRecord::Relation)
        expect(result.to_a.size).to eq(2)
      end
    end

    context "with limit: nil" do
      it "returns all records without pagination" do
        result = repository.search({}, limit: nil)
        expect(result).to be_a(ActiveRecord::Relation)
        expect(result.to_a.size).to be >= 3
      end
    end

    context "with pagination" do
      it "respects page and per_page parameters" do
        result = repository.search({}, page: 1, per_page: 1, limit: :default)
        expect(result.to_a.size).to eq(1)
      end

      it "calculates correct offset for page 2" do
        result = repository.search({}, page: 2, per_page: 1, limit: :default)
        expect(result.to_a.size).to eq(1)
      end

      it "handles page 0 as page 1" do
        result_page_0 = repository.search({}, page: 0, per_page: 10, limit: :default)
        result_page_1 = repository.search({}, page: 1, per_page: 10, limit: :default)
        expect(result_page_0.to_a).to eq(result_page_1.to_a)
      end
    end

    context "with order" do
      it "orders results by string" do
        result = repository.search({}, order: "name ASC", limit: nil)
        names = result.to_a.map(&:name)
        expect(names).to eq(names.sort)
      end

      it "orders results by hash" do
        result = repository.search({}, order: { name: :desc }, limit: nil)
        names = result.to_a.map(&:name)
        expect(names).to eq(names.sort.reverse)
      end
    end

    context "with includes" do
      it "applies includes for eager loading" do
        # User has_many :bookings
        result = repository.search({}, includes: [ :bookings ], limit: nil)
        expect(result.includes_values).to include(:bookings)
      end
    end

    context "with joins" do
      it "applies joins" do
        # Create a booking for user1 so join has data
        Booking.create!(user: user1, title: "Test", date: Date.today)

        result = repository.search({}, joins: [ :bookings ], limit: nil)
        expect(result.joins_values).to include(:bookings)
      end
    end

    context "with predicates" do
      # Note: This test only works if User model has a `search` method
      # If not, it falls back to model.all
      it "cleans nil values from predicates" do
        # Passing nil predicates should not cause errors
        result = repository.search({ name: nil }, limit: nil)
        expect(result).to be_a(ActiveRecord::Relation)
      end
    end
  end

  describe "delegated methods" do
    describe "#find" do
      it "finds record by id" do
        found = repository.find(user1.id)
        expect(found).to eq(user1)
      end

      it "raises RecordNotFound for invalid id" do
        expect { repository.find(999999) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe "#find_by" do
      it "finds record by attributes" do
        found = repository.find_by(email: "alice@example.com")
        expect(found).to eq(user1)
      end

      it "returns nil when not found" do
        found = repository.find_by(email: "nonexistent@example.com")
        expect(found).to be_nil
      end
    end

    describe "#where" do
      it "returns matching records" do
        results = repository.where(admin: true)
        expect(results.to_a).to include(user2)
        expect(results.all? { |u| u.admin? }).to be true
      end
    end

    describe "#all" do
      it "returns all records" do
        results = repository.all
        expect(results.to_a).to include(user1, user2, user3)
      end
    end

    describe "#count" do
      it "returns count of records" do
        expect(repository.count).to be >= 3
      end
    end

    describe "#exists?" do
      it "returns true when records exist" do
        expect(repository.exists?(admin: true)).to be true
      end

      it "returns false when no records match" do
        expect(repository.exists?(email: "nonexistent@example.com")).to be false
      end
    end
  end

  describe "#build" do
    it "returns an unsaved record" do
      user = repository.build(name: "New User", email: "new@example.com")
      expect(user).to be_new_record
      expect(user.name).to eq("New User")
    end
  end

  describe "#new" do
    it "is an alias for build" do
      expect(repository.method(:new)).to eq(repository.method(:build))
    end
  end

  describe "#create" do
    it "creates and persists a record" do
      user = repository.create(name: "Created", email: "created@example.com")
      expect(user).to be_persisted
    end

    it "returns invalid record on validation failure" do
      user = repository.create(name: nil) # name is required
      expect(user).not_to be_valid
      expect(user).not_to be_persisted
    end
  end

  describe "#create!" do
    it "creates and persists a record" do
      user = repository.create!(name: "Created!", email: "created_bang@example.com")
      expect(user).to be_persisted
      expect(user.name).to eq("Created!")
    end

    it "raises on validation failure" do
      expect {
        repository.create!(name: nil)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "#update" do
    it "updates a record object" do
      repository.update(user1, name: "Updated Alice")
      expect(user1.reload.name).to eq("Updated Alice")
    end

    it "updates a record by ID" do
      repository.update(user1.id, name: "Updated by ID")
      expect(user1.reload.name).to eq("Updated by ID")
    end

    it "raises on validation failure" do
      expect {
        repository.update(user1, name: nil)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "#update!" do
    it "is an alias for update" do
      expect(repository.method(:update!)).to eq(repository.method(:update))
    end
  end

  describe "#destroy" do
    it "destroys a record object" do
      user_to_destroy = User.create!(name: "To Destroy", email: "destroy@example.com")
      user_id = user_to_destroy.id

      repository.destroy(user_to_destroy)
      expect(User.find_by(id: user_id)).to be_nil
    end

    it "destroys a record by ID" do
      user_to_destroy = User.create!(name: "To Destroy by ID", email: "destroy_id@example.com")
      user_id = user_to_destroy.id

      repository.destroy(user_id)
      expect(User.find_by(id: user_id)).to be_nil
    end
  end

  describe "#destroy!" do
    it "is an alias for destroy" do
      expect(repository.method(:destroy!)).to eq(repository.method(:destroy))
    end
  end

  describe "#delete" do
    it "deletes a record without callbacks" do
      user_to_delete = User.create!(name: "To Delete", email: "delete@example.com")
      user_id = user_to_delete.id

      result = repository.delete(user_to_delete)
      expect(result).to eq(1)
      expect(User.find_by(id: user_id)).to be_nil
    end

    it "deletes a record by ID" do
      user_to_delete = User.create!(name: "To Delete by ID", email: "delete_id@example.com")
      user_id = user_to_delete.id

      result = repository.delete(user_id)
      expect(result).to eq(1)
      expect(User.find_by(id: user_id)).to be_nil
    end

    it "returns 0 when record doesn't exist" do
      result = repository.delete(999999)
      expect(result).to eq(0)
    end
  end

  describe "private methods via public interface" do
    describe "#resolve_record" do
      it "returns record when passed a record object" do
        # update method uses resolve_record internally
        repository.update(user1, name: "Via Object")
        expect(user1.reload.name).to eq("Via Object")
      end

      it "finds record when passed an ID" do
        repository.update(user1.id, name: "Via ID")
        expect(user1.reload.name).to eq("Via ID")
      end
    end
  end
end
