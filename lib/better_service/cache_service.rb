# frozen_string_literal: true

module BetterService
  # CacheService - Provides cache invalidation and management for BetterService
  #
  # This service handles cache invalidation based on contexts defined in
  # the Cacheable concern. It provides methods to invalidate cache keys
  # for specific users, contexts, or globally.
  #
  # Supports cascading invalidation through INVALIDATION_MAP - when a context
  # is invalidated, all related contexts are also invalidated automatically.
  #
  # @example Invalidate cache for a specific context and user
  #   BetterService::CacheService.invalidate_for_context(current_user, "products")
  #
  # @example Invalidate cache globally for a context
  #   BetterService::CacheService.invalidate_global("sidebar")
  #
  # @example Invalidate all cache for a user
  #   BetterService::CacheService.invalidate_for_user(current_user)
  #
  # @example Configure invalidation map
  #   BetterService::CacheService.configure_invalidation_map(
  #     'products' => %w[products inventory reports],
  #     'orders' => %w[orders products reports]
  #   )
  class CacheService
    # Default invalidation map - can be customized via configure_invalidation_map
    # Maps primary context to array of contexts that should be invalidated together
    #
    # @return [Hash<String, Array<String>>] Context invalidation mappings
    @invalidation_map = {}

    class << self
      # Get the current invalidation map
      #
      # @return [Hash<String, Array<String>>] Current invalidation mappings
      attr_reader :invalidation_map

      # Configure the invalidation map for cascading cache invalidation
      #
      # The invalidation map defines which cache contexts should be invalidated
      # together. When a primary context is invalidated, all related contexts
      # in the map are also invalidated.
      #
      # @param map [Hash<String, Array<String>>] Invalidation mappings
      # @return [void]
      #
      # @example Configure invalidation relationships
      #   BetterService::CacheService.configure_invalidation_map(
      #     'products' => %w[products inventory reports],
      #     'orders' => %w[orders products reports],
      #     'users' => %w[users orders reports],
      #     'categories' => %w[categories products reports],
      #     'inventory' => %w[inventory products reports]
      #   )
      def configure_invalidation_map(map)
        @invalidation_map = map.transform_keys(&:to_s).transform_values do |contexts|
          Array(contexts).map(&:to_s)
        end.freeze
      end

      # Add entries to the invalidation map without replacing existing ones
      #
      # @param entries [Hash<String, Array<String>>] New invalidation mappings to add
      # @return [void]
      #
      # @example Add new context invalidation rules
      #   BetterService::CacheService.add_invalidation_rules(
      #     'payments' => %w[payments statistics invoices]
      #   )
      def add_invalidation_rules(entries)
        new_entries = entries.transform_keys(&:to_s).transform_values do |contexts|
          Array(contexts).map(&:to_s)
        end
        @invalidation_map = (@invalidation_map || {}).merge(new_entries).freeze
      end

      # Get all contexts that should be invalidated for a given context
      #
      # If the context exists in the invalidation map, returns all mapped contexts.
      # Otherwise, returns an array containing just the original context.
      #
      # @param context [String, Symbol] The primary context
      # @return [Array<String>] All contexts to invalidate
      #
      # @example
      #   contexts_for('products')  # => ['products', 'inventory', 'reports']
      #   contexts_for('unknown')   # => ['unknown']
      def contexts_to_invalidate(context)
        context_str = context.to_s
        (@invalidation_map || {})[context_str] || [ context_str ]
      end

      # Invalidate cache for a specific context and user
      #
      # Deletes all cache keys that match the pattern for the given user and context.
      # Uses cascading invalidation - if the context exists in the invalidation map,
      # all related contexts will also be invalidated.
      #
      # This is useful when data changes that affects a specific user's cached results.
      #
      # @param user [Object] The user whose cache should be invalidated
      # @param context [String] The context name (e.g., "products", "sidebar")
      # @param async [Boolean] Whether to perform invalidation asynchronously
      # @param cascade [Boolean] Whether to use cascading invalidation (default: true)
      # @return [Integer] Number of keys deleted (if supported by cache store)
      #
      # @example Basic invalidation
      #   # After creating a product, invalidate products cache for user
      #   BetterService::CacheService.invalidate_for_context(user, "products")
      #
      # @example With cascading (if map configured for orders -> [orders, products, reports])
      #   BetterService::CacheService.invalidate_for_context(user, "orders")
      #   # Invalidates: orders, products, reports caches
      #
      # @example Without cascading
      #   BetterService::CacheService.invalidate_for_context(user, "orders", cascade: false)
      #   # Invalidates: only orders cache
      def invalidate_for_context(user, context, async: false, cascade: true)
        return 0 unless user && context && !context.to_s.strip.empty?

        # Get all contexts to invalidate (cascading or single)
        contexts = cascade ? contexts_to_invalidate(context) : [ context.to_s ]
        total_deleted = 0

        contexts.each do |ctx|
          pattern = build_user_context_pattern(user, ctx)

          if async
            invalidate_async(pattern)
          else
            result = delete_matched(pattern)
            count = result.is_a?(Array) ? result.size : (result || 0)
            total_deleted += count
          end
        end

        log_cascading_invalidation(context, contexts) if cascade && contexts.size > 1
        total_deleted
      end

      # Invalidate cache globally for a context
      #
      # Deletes all cache keys for the given context across all users.
      # Uses cascading invalidation - if the context exists in the invalidation map,
      # all related contexts will also be invalidated.
      #
      # This is useful when data changes that affects everyone (e.g., global settings).
      #
      # @param context [String] The context name
      # @param async [Boolean] Whether to perform invalidation asynchronously
      # @param cascade [Boolean] Whether to use cascading invalidation (default: true)
      # @return [Integer] Number of keys deleted (if supported by cache store)
      #
      # @example Basic global invalidation
      #   # After updating global sidebar settings
      #   BetterService::CacheService.invalidate_global("sidebar")
      #
      # @example With cascading
      #   BetterService::CacheService.invalidate_global("orders")
      #   # Invalidates: orders, products, reports caches globally
      def invalidate_global(context, async: false, cascade: true)
        return 0 unless context && !context.to_s.strip.empty?

        # Get all contexts to invalidate (cascading or single)
        contexts = cascade ? contexts_to_invalidate(context) : [ context.to_s ]
        total_deleted = 0

        contexts.each do |ctx|
          pattern = build_global_context_pattern(ctx)

          if async
            invalidate_async(pattern)
          else
            result = delete_matched(pattern)
            count = result.is_a?(Array) ? result.size : (result || 0)
            total_deleted += count
          end
        end

        log_cascading_invalidation(context, contexts, global: true) if cascade && contexts.size > 1
        total_deleted
      end

      # Invalidate all cache for a specific user
      #
      # Deletes all cache keys associated with the given user.
      # This is useful when a user logs out or their permissions change.
      #
      # @param user [Object] The user whose cache should be invalidated
      # @param async [Boolean] Whether to perform invalidation asynchronously
      # @return [Integer] Number of keys deleted (if supported by cache store)
      #
      # @example
      #   # After user role changes
      #   BetterService::CacheService.invalidate_for_user(current_user)
      def invalidate_for_user(user, async: false)
        return 0 unless user

        pattern = build_user_pattern(user)

        if async
          invalidate_async(pattern)
          0
        else
          result = delete_matched(pattern)
          # Ensure we return Integer, not Array
          result.is_a?(Array) ? result.size : (result || 0)
        end
      end

      # Invalidate specific cache key
      #
      # Deletes a single cache key. Useful when you know the exact key.
      #
      # @param key [String] The cache key to delete
      # @return [Boolean] true if deleted, false otherwise
      #
      # @example
      #   BetterService::CacheService.invalidate_key("products_index:user_123:abc123")
      def invalidate_key(key)
        return false unless key && !key.to_s.strip.empty?

        Rails.cache.delete(key)
        true
      rescue ArgumentError
        # Rails.cache.delete raises ArgumentError for invalid keys
        false
      end

      # Clear all BetterService cache
      #
      # WARNING: This deletes ALL cache keys that match BetterService patterns.
      # Use with caution, preferably only in development/testing.
      #
      # @return [Integer] Number of keys deleted (if supported by cache store)
      #
      # @example
      #   # In test setup
      #   BetterService::CacheService.clear_all
      def clear_all
        pattern = "*:user_*:*" # Match all BetterService cache keys
        result = delete_matched(pattern)
        # Ensure we return Integer, not Array
        result.is_a?(Array) ? result.size : (result || 0)
      end

      # Fetch from cache with block
      #
      # Wrapper around Rails.cache.fetch with BetterService conventions.
      # If the key exists, returns cached value. Otherwise, executes block,
      # caches the result, and returns it.
      #
      # @param key [String] The cache key
      # @param options [Hash] Options passed to Rails.cache.fetch
      # @option options [Integer] :expires_in TTL in seconds
      # @option options [Boolean] :force Force cache refresh
      # @return [Object] The cached or computed value
      #
      # @example
      #   result = BetterService::CacheService.fetch("my_key", expires_in: 1.hour) do
      #     expensive_computation
      #   end
      def fetch(key, options = {}, &block)
        Rails.cache.fetch(key, options, &block)
      end

      # Check if a key exists in cache
      #
      # @param key [String] The cache key to check
      # @return [Boolean] true if key exists, false otherwise
      def exist?(key)
        return false unless key && !key.to_s.strip.empty?

        Rails.cache.exist?(key)
      end

      # Get cache statistics
      #
      # Returns information about cache store and BetterService cache usage.
      # Note: Detailed stats only available with certain cache stores (Redis).
      #
      # @return [Hash] Cache statistics
      def stats
        {
          cache_store: Rails.cache.class.name,
          supports_pattern_deletion: supports_delete_matched?,
          supports_async: defined?(ActiveJob) ? true : false,
          invalidation_map_configured: (@invalidation_map || {}).any?,
          invalidation_map_contexts: (@invalidation_map || {}).keys
        }
      end

      private

      # Build cache key pattern for user + context
      #
      # @param user [Object] User object with id
      # @param context [String] Context name
      # @return [String] Pattern like "*:user_123:*:products"
      def build_user_context_pattern(user, context)
        user_id = user.respond_to?(:id) ? user.id : user
        "*:user_#{user_id}:*:#{context}"
      end

      # Build cache key pattern for global context
      #
      # @param context [String] Context name
      # @return [String] Pattern like "*:#{context}"
      def build_global_context_pattern(context)
        "*:#{context}"
      end

      # Build cache key pattern for user (all contexts)
      #
      # @param user [Object] User object with id
      # @return [String] Pattern like "*:user_123:*"
      def build_user_pattern(user)
        user_id = user.respond_to?(:id) ? user.id : user
        "*:user_#{user_id}:*"
      end

      # Delete cache keys matching pattern
      #
      # Uses Rails.cache.delete_matched if supported by cache store.
      # Falls back to no-op if not supported (e.g., MemoryStore).
      #
      # @param pattern [String] Pattern with wildcards
      # @return [Integer] Number of keys deleted (0 if not supported)
      def delete_matched(pattern)
        if supports_delete_matched?
          # Convert wildcard pattern to regex for Rails.cache.delete_matched
          # Pattern like "*:user_123:*:products" becomes /.*:user_123:.*:products/
          regex_pattern = convert_pattern_to_regex(pattern)
          count = Rails.cache.delete_matched(regex_pattern)
          log_invalidation(pattern, count)
          count || 0
        else
          log_warning("Cache store #{Rails.cache.class.name} does not support pattern deletion")
          0
        end
      end

      # Convert wildcard pattern to Regexp
      #
      # @param pattern [String] Pattern with * wildcards
      # @return [Regexp] Regexp for matching cache keys
      def convert_pattern_to_regex(pattern)
        return // unless pattern

        # Escape special regex characters except *
        escaped = Regexp.escape(pattern.to_s)
        # Replace escaped \* with .* for regex matching
        regex_string = escaped.gsub('\*', ".*")
        Regexp.new(regex_string)
      end

      # Invalidate cache asynchronously using ActiveJob
      #
      # @param pattern [String] Pattern to invalidate
      # @return [void]
      def invalidate_async(pattern)
        if defined?(ActiveJob)
          CacheInvalidationJob.perform_later(pattern)
          log_invalidation(pattern, "async")
        else
          # Fallback to synchronous if ActiveJob not available
          delete_matched(pattern)
        end
      end

      # Check if cache store supports delete_matched
      #
      # @return [Boolean]
      def supports_delete_matched?
        Rails.cache.respond_to?(:delete_matched)
      end

      # Log cache invalidation
      #
      # @param pattern [String] Pattern invalidated
      # @param count [Integer, String] Number of keys or "async"
      # @return [void]
      def log_invalidation(pattern, count)
        return unless defined?(Rails) && Rails.logger

        if count == "async"
          Rails.logger.info "[BetterService::CacheService] Async invalidation queued: #{pattern}"
        else
          Rails.logger.info "[BetterService::CacheService] Invalidated #{count} keys matching: #{pattern}"
        end
      end

      # Log warning
      #
      # @param message [String] Warning message
      # @return [void]
      def log_warning(message)
        return unless defined?(Rails) && Rails.logger

        Rails.logger.warn "[BetterService::CacheService] #{message}"
      end

      # Log cascading invalidation
      #
      # @param primary_context [String] The primary context that triggered invalidation
      # @param all_contexts [Array<String>] All contexts that were invalidated
      # @param global [Boolean] Whether this was a global invalidation
      # @return [void]
      def log_cascading_invalidation(primary_context, all_contexts, global: false)
        return unless defined?(Rails) && Rails.logger

        scope = global ? "globally" : "for user"
        Rails.logger.info "[BetterService::CacheService] Cascading invalidation #{scope}: " \
                          "'#{primary_context}' -> [#{all_contexts.join(', ')}]"
      end
    end

    # ActiveJob for async cache invalidation
    #
    # This job is only defined if ActiveJob is available.
    # It allows cache invalidation to happen in the background.
    if defined?(ActiveJob)
      class CacheInvalidationJob < ActiveJob::Base
        queue_as :default

        # Perform cache invalidation
        #
        # @param pattern [String] Cache key pattern to invalidate
        def perform(pattern)
          BetterService::CacheService.send(:delete_matched, pattern)
        end
      end
    end
  end
end
