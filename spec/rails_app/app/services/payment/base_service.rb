# frozen_string_literal: true

class Payment::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  messages_namespace :payments
  cache_contexts :payments, :orders
  repository :payment
end
