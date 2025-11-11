# frozen_string_literal: true

require "digest"

module BetterService
  module Concerns
    module Serviceable
    module Cacheable
      extend ActiveSupport::Concern

      included do
        class_attribute :_cache_key, default: nil
        class_attribute :_cache_ttl, default: 900  # 15 minutes in seconds
        class_attribute :_cache_contexts, default: []

        # Wrap call method with caching after class is loaded
        # This is safe because included runs after Base defines call
        if method_defined?(:call)
          alias_method :call_without_cache, :call

          define_method(:call) do
            return call_without_cache unless cache_enabled?

            cache_key_value = build_cache_key(user)

            # Check if cache exists to publish appropriate event
            cache_exists = Rails.cache.exist?(cache_key_value)

            # Get cache context if available
            cache_context = self.class._cache_contexts.first

            # Publish cache hit/miss event if instrumentation methods are available
            # These methods are added by Instrumentation concern which is prepended after
            begin
              if cache_exists
                publish_cache_hit(cache_key_value, cache_context)
              else
                publish_cache_miss(cache_key_value, cache_context)
              end
            rescue NoMethodError
              # Instrumentation methods not available - skip event publishing silently
            end

            Rails.cache.fetch(cache_key_value, expires_in: self.class._cache_ttl) do
              call_without_cache
            end
          end
        end
      end

      class_methods do
        def cache_key(key)
          self._cache_key = key
        end

        def cache_ttl(duration)
          self._cache_ttl = duration
        end

        def cache_contexts(*contexts)
          self._cache_contexts = contexts
        end
      end

      private

      def cache_enabled?
        self.class._cache_key.present?
      end

      def build_cache_key(user)
        user_part = user ? "user_#{user.id}" : "global"
        "#{self.class._cache_key}:#{user_part}:#{cache_params_signature}"
      end

      def cache_params_signature
        Digest::MD5.hexdigest(@params.to_json)
      end

      def invalidate_cache_for(user = nil)
        return unless self.class._cache_contexts.present?

        if user.present?
          self.class._cache_contexts.each do |context|
            CacheService.invalidate_for_context(user, context)
          end
        else
          Rails.logger.info "[BetterService] Global cache invalidation for: #{self.class._cache_contexts.join(', ')}" if defined?(Rails)
          self.class._cache_contexts.each do |context|
            CacheService.invalidate_global(context)
          end
        end
      end
    end
    end
  end
end
