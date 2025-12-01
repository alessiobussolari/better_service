# frozen_string_literal: true

module BetterService
  # Result wrapper per le risposte dei service
  #
  # Fornisce un modo standardizzato per restituire sia la risorsa che i metadata.
  # BetterController può automaticamente unwrappare gli oggetti Result.
  #
  # @example Caso di successo
  #   BetterService::Result.new(user, meta: { message: "Created" })
  #
  # @example Caso di fallimento
  #   BetterService::Result.new(user, meta: { success: false, message: "Validation failed" })
  #
  class Result
    attr_reader :resource, :meta

    # @param resource [Object] L'oggetto risorsa (model, collection, etc.)
    # @param meta [Hash] Hash di metadata, deve contenere :success key (default: true)
    def initialize(resource, meta: {})
      @resource = resource
      @meta     = meta.is_a?(Hash) ? meta.reverse_merge(success: true) : { success: true }
    end

    # @return [Boolean] true se l'operazione è riuscita
    def success?
      meta[:success] == true
    end

    # @return [Boolean] true se l'operazione è fallita
    def failure?
      !success?
    end

    # @return [String, nil] Il messaggio dal meta
    def message
      meta[:message]
    end

    # @return [Symbol, nil] L'azione eseguita
    def action
      meta[:action]
    end

    # @return [Hash, nil] Gli errori di validazione
    def validation_errors
      meta[:validation_errors]
    end

    # @return [Array<String>, nil] I messaggi di errore completi
    def full_messages
      meta[:full_messages]
    end

    # @return [ActiveModel::Errors, nil] Errori dalla risorsa se disponibili
    def errors
      resource.respond_to?(:errors) ? resource.errors : nil
    end

    # Supporta destructuring: resource, meta = result
    # @return [Array] [resource, meta]
    def to_ary
      [ resource, meta ]
    end

    # Alias per compatibilità con destructuring
    alias_method :deconstruct, :to_ary

    # @return [Hash] Rappresentazione completa
    def to_h
      { resource: resource, meta: meta }
    end

    # Accesso Hash-like per compatibilità con BetterController
    # @param key [Symbol] La chiave da accedere
    # @return [Object, nil] Il valore associato alla chiave
    def [](key)
      case key
      when :resource then resource
      when :meta then meta
      when :success then success?
      when :message then message
      when :action then action
      else
        meta[key]
      end
    end

    # Accesso nested Hash-like (dig)
    # @param keys [Array<Symbol>] Le chiavi per l'accesso nested
    # @return [Object, nil] Il valore nested
    def dig(*keys)
      return nil if keys.empty?

      value = self[keys.first]
      return value if keys.size == 1
      return nil unless value.respond_to?(:dig)

      value.dig(*keys[1..])
    end

    # Verifica esistenza chiave
    # @param key [Symbol] La chiave da verificare
    # @return [Boolean]
    def key?(key)
      %i[resource meta success message action].include?(key) || meta.key?(key)
    end
    alias_method :has_key?, :key?
  end
end
