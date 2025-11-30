# frozen_string_literal: true

class Inventory::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  messages_namespace :inventory
  cache_contexts :inventory, :products
  repository :product
end
