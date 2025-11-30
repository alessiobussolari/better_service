# frozen_string_literal: true

class Order::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  messages_namespace :orders
  cache_contexts :orders
  repository :order
end
