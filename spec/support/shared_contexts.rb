# frozen_string_literal: true

# Shared context for tests requiring a user
RSpec.shared_context "with user" do
  let(:user) { create(:user) }
end

# Shared context for tests requiring an admin user
RSpec.shared_context "with admin user" do
  let(:user) { create(:user, :admin) }
end

# Shared context for tests requiring a product
RSpec.shared_context "with product" do
  include_context "with user"
  let(:product) { create(:product, user: user) }
end

# Shared context for tests requiring a booking
RSpec.shared_context "with booking" do
  include_context "with user"
  let(:booking) { create(:booking, user: user) }
end
